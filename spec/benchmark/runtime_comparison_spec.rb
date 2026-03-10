require "benchmark"
require "fileutils"
require "tmpdir"
require "sequel"

RSpec.describe "runtime benchmarks", :benchmark do
  ITERATIONS = Integer(ENV.fetch("ACTIVE_VERSION_BENCH_ITERATIONS", "5000"))
  WARMUP = Integer(ENV.fetch("ACTIVE_VERSION_BENCH_WARMUP", "200"))
  ROUNDS = Integer(ENV.fetch("ACTIVE_VERSION_BENCH_ROUNDS", "5"))
  BENCH_DB = ENV.fetch("BENCH_DB", "sqlite").downcase

  class BenchBase < ActiveRecord::Base
    self.abstract_class = true
  end

  class BenchBaselinePost < BenchBase
    self.table_name = "bench_baseline_posts"
  end

  class BenchAvPostAudit < BenchBase
    self.table_name = "bench_av_post_audits"
    include ActiveVersion::Audits::AuditRecord
  end

  class BenchAvPost < BenchBase
    self.table_name = "bench_av_posts"
    include ActiveVersion::Audits::HasAudits

    has_audits as: BenchAvPostAudit, on: [:create, :update]
  end

  class BenchTriggerPost < BenchBase
    self.table_name = "bench_trigger_posts"
  end

  def sqlite?
    BENCH_DB == "sqlite"
  end

  def postgresql?
    BENCH_DB == "postgresql"
  end

  def benchmark_db_path
    @benchmark_db_path ||= File.join(Dir.tmpdir, "active_version_benchmark_#{Process.pid}.sqlite3")
  end

  def benchmark_connection_config
    if sqlite?
      {adapter: "sqlite3", database: benchmark_db_path}
    elsif postgresql?
      {
        adapter: "postgresql",
        database: ENV["BENCH_PG_DATABASE"] || ENV["PGDATABASE"] || "postgres",
        host: ENV["BENCH_PG_HOST"] || ENV["PGHOST"] || "127.0.0.1",
        port: Integer(ENV["BENCH_PG_PORT"] || ENV["PGPORT"] || "5432"),
        username: ENV["BENCH_PG_USER"] || ENV["PGUSER"] || ENV["USER"],
        password: ENV["BENCH_PG_PASSWORD"] || ENV["PGPASSWORD"]
      }.compact
    else
      raise ArgumentError, "Unsupported BENCH_DB=#{BENCH_DB.inspect}; use sqlite or postgresql"
    end
  end

  def sequel_connection
    if sqlite?
      Sequel.sqlite(benchmark_db_path)
    else
      Sequel.connect(
        adapter: "postgres",
        database: benchmark_connection_config[:database],
        host: benchmark_connection_config[:host],
        port: benchmark_connection_config[:port],
        user: benchmark_connection_config[:username],
        password: benchmark_connection_config[:password]
      )
    end
  end

  def reset_rows!
    BenchBaselinePost.delete_all
    BenchAvPost.delete_all
    BenchAvPostAudit.delete_all
    BenchTriggerPost.delete_all
    BenchBase.connection.execute("DELETE FROM bench_trigger_post_audits")
    @sequel_db[:sequel_posts].delete
    @sequel_db[:sequel_av_posts].delete
    @sequel_db[:sequel_av_post_audits].delete
    @sequel_db[:sequel_av_post_revisions].delete
  end

  def profile(label)
    samples_ms = []

    ROUNDS.times do |round|
      GC.start
      elapsed = Benchmark.realtime { yield(round) }
      samples_ms << (elapsed * 1000.0)
    end

    sorted = samples_ms.sort
    p5_idx = [(ROUNDS * 0.05).floor, 0].max
    p95_idx = [(ROUNDS * 0.95).ceil - 1, 0].max
    median_ms = sorted[ROUNDS / 2]
    avg_ms = samples_ms.sum / samples_ms.length.to_f
    p5_ms = sorted[p5_idx]
    p95_ms = sorted[p95_idx]

    per_op_samples = samples_ms.map { |sample_ms| sample_ms / ITERATIONS.to_f }
    per_op_sorted = per_op_samples.sort
    per_op_p5_ms = per_op_sorted[p5_idx]
    per_op_mean_ms = per_op_samples.sum / per_op_samples.length.to_f
    per_op_p95_ms = per_op_sorted[p95_idx]

    {
      label: label,
      rounds: ROUNDS,
      avg_ms: avg_ms,
      median_ms: median_ms,
      p5_ms: p5_ms,
      p95_ms: p95_ms,
      per_op_median_ms: (median_ms / ITERATIONS.to_f),
      per_op_p5_ms: per_op_p5_ms,
      per_op_mean_ms: per_op_mean_ms,
      per_op_p95_ms: per_op_p95_ms,
      ops_per_second: (ITERATIONS / (median_ms / 1000.0))
    }
  end

  def install_triggers!
    if sqlite?
      BenchBase.connection.execute(<<~SQL)
        CREATE TRIGGER bench_trigger_posts_insert_audit
        AFTER INSERT ON bench_trigger_posts
        BEGIN
          INSERT INTO bench_trigger_post_audits
            (auditable_id, auditable_type, action, audited_changes, version, created_at, updated_at)
          VALUES
            (NEW.id, 'BenchTriggerPost', 'create', '{}', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
        END;
      SQL

      BenchBase.connection.execute(<<~SQL)
        CREATE TRIGGER bench_trigger_posts_update_audit
        AFTER UPDATE ON bench_trigger_posts
        BEGIN
          INSERT INTO bench_trigger_post_audits
            (auditable_id, auditable_type, action, audited_changes, version, created_at, updated_at)
          VALUES
            (
              NEW.id,
              'BenchTriggerPost',
              'update',
              '{}',
              COALESCE((SELECT MAX(version) + 1 FROM bench_trigger_post_audits WHERE auditable_id = NEW.id), 1),
              CURRENT_TIMESTAMP,
              CURRENT_TIMESTAMP
            );
        END;
      SQL
    else
      BenchBase.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION bench_trigger_posts_audit_insert_fn()
        RETURNS trigger AS $$
        BEGIN
          INSERT INTO bench_trigger_post_audits
            (auditable_id, auditable_type, action, audited_changes, version, created_at, updated_at)
          VALUES
            (NEW.id, 'BenchTriggerPost', 'create', '{}', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      BenchBase.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION bench_trigger_posts_audit_update_fn()
        RETURNS trigger AS $$
        BEGIN
          INSERT INTO bench_trigger_post_audits
            (auditable_id, auditable_type, action, audited_changes, version, created_at, updated_at)
          VALUES
            (
              NEW.id,
              'BenchTriggerPost',
              'update',
              '{}',
              COALESCE((SELECT MAX(version) + 1 FROM bench_trigger_post_audits WHERE auditable_id = NEW.id), 1),
              CURRENT_TIMESTAMP,
              CURRENT_TIMESTAMP
            );
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      BenchBase.connection.execute(<<~SQL)
        CREATE TRIGGER bench_trigger_posts_insert_audit
        AFTER INSERT ON bench_trigger_posts
        FOR EACH ROW EXECUTE FUNCTION bench_trigger_posts_audit_insert_fn();
      SQL

      BenchBase.connection.execute(<<~SQL)
        CREATE TRIGGER bench_trigger_posts_update_audit
        AFTER UPDATE ON bench_trigger_posts
        FOR EACH ROW EXECUTE FUNCTION bench_trigger_posts_audit_update_fn();
      SQL
    end
  end

  before(:all) do
    FileUtils.rm_f(benchmark_db_path) if sqlite?
    BenchBase.establish_connection(benchmark_connection_config)
    ActiveRecord::Base.establish_connection(benchmark_connection_config)

    puts "[benchmark] adapter=#{BENCH_DB}"

    ActiveRecord::Schema.define do
      create_table :bench_baseline_posts, force: true do |t|
        t.string :title
        t.string :status
        t.timestamps
      end

      create_table :bench_av_posts, force: true do |t|
        t.string :title
        t.string :status
        t.timestamps
      end

      create_table :bench_av_post_audits, force: true do |t|
        t.integer :auditable_id, null: false
        t.string :auditable_type, null: false
        t.string :action, null: false
        t.text :audited_changes
        t.integer :version, null: false
        t.integer :user_id
        t.text :comment
        t.text :audited_context
        t.string :remote_address
        t.string :request_uuid
        t.timestamps
      end

      add_index :bench_av_post_audits, [:auditable_type, :auditable_id, :version],
        unique: true, name: "index_bench_av_post_audits_on_auditable_and_version"

      create_table :bench_trigger_posts, force: true do |t|
        t.string :title
        t.string :status
        t.timestamps
      end

      create_table :bench_trigger_post_audits, force: true do |t|
        t.integer :auditable_id, null: false
        t.string :auditable_type, null: false
        t.string :action, null: false
        t.text :audited_changes
        t.integer :version, null: false
        t.timestamps
      end
    end

    install_triggers!

    @sequel_db = sequel_connection
    @sequel_db.create_table?(:sequel_posts) do
      primary_key :id
      String :title
      String :status
      DateTime :created_at
      DateTime :updated_at
    end

    @sequel_db.create_table?(:sequel_av_posts) do
      primary_key :id
      String :title
      String :status
      DateTime :created_at
      DateTime :updated_at
    end

    @sequel_db.create_table?(:sequel_av_post_revisions) do
      primary_key :id
      foreign_key :sequel_av_post_id, :sequel_av_posts, null: false, on_delete: :cascade
      Integer :version, null: false
      String :title
      String :status
      DateTime :created_at
      DateTime :updated_at
      index [:sequel_av_post_id, :version], unique: true
    end

    @sequel_db.create_table?(:sequel_av_post_audits) do
      primary_key :id
      foreign_key :sequel_av_post_id, :sequel_av_posts, null: false, on_delete: :cascade
      Integer :version, null: false
      String :action, null: false
      String :audited_changes, text: true, null: false
      String :audited_context, text: true, null: false, default: "{}"
      DateTime :created_at
      DateTime :updated_at
      index [:sequel_av_post_id, :version], unique: true
    end

    sequel_db = @sequel_db
    @bench_sequel_post_class = Class.new(Sequel::Model(sequel_db[:sequel_posts]))
    @bench_sequel_av_revision_class = Class.new(Sequel::Model(sequel_db[:sequel_av_post_revisions]))
    @bench_sequel_av_audit_class = Class.new(Sequel::Model(sequel_db[:sequel_av_post_audits]))
    revision_class = @bench_sequel_av_revision_class
    audit_class = @bench_sequel_av_audit_class
    @bench_sequel_av_post_class = Class.new(Sequel::Model(sequel_db[:sequel_av_posts])) do
      plugin ActiveVersion::Adapters::Sequel::Versioning
      active_version(
        revision_model: revision_class,
        audit_model: audit_class,
        foreign_key: :sequel_av_post_id,
        tracked_columns: %i[title status]
      )
    end
  end

  after(:all) do
    @sequel_db&.disconnect
    BenchBase.connection_pool.disconnect!
    ActiveRecord::Base.connection_pool.disconnect!
    FileUtils.rm_f(benchmark_db_path) if sqlite?
  end

  it "profiles ActiveRecord and Sequel groups separately" do
    warmup_payload = {title: "warmup", status: "draft"}
    WARMUP.times do
      record = BenchBaselinePost.create!(warmup_payload)
      record.update!(status: "published")
      record.destroy!
    end

    baseline = profile("activerecord_baseline") do |round|
      reset_rows!
      ITERATIONS.times do |i|
        row = BenchBaselinePost.create!(title: "baseline-r#{round}-#{i}", status: "draft")
        row.update!(status: "published")
      end
    end

    active_version = profile("active_version_audit") do |round|
      reset_rows!
      ActiveVersion.with_context(user_id: 1, source: "benchmark", round: round) do
        ITERATIONS.times do |i|
          row = BenchAvPost.create!(title: "av-r#{round}-#{i}", status: "draft")
          row.update!(status: "published")
        end
      end
    end
    active_version_audit_count = BenchAvPostAudit.count

    trigger_style = profile("db_trigger_audit") do |round|
      reset_rows!
      ITERATIONS.times do |i|
        row = BenchTriggerPost.create!(title: "trigger-r#{round}-#{i}", status: "draft")
        row.update!(status: "published")
      end
    end
    trigger_audit_count = BenchBase.connection.select_value("SELECT COUNT(*) FROM bench_trigger_post_audits").to_i

    sequel_baseline = profile("sequel_baseline") do |round|
      reset_rows!
      now = Time.now
      ITERATIONS.times do |i|
        row = @bench_sequel_post_class.create(title: "sequel-r#{round}-#{i}", status: "draft", created_at: now, updated_at: now)
        row.update(status: "published", updated_at: Time.now)
      end
    end
    sequel_av = profile("sequel_active_version") do |round|
      reset_rows!
      now = Time.now
      ActiveVersion.with_context(source: "benchmark", round: round, adapter: "sequel") do
        ITERATIONS.times do |i|
          row = @bench_sequel_av_post_class.create(title: "sequel-av-r#{round}-#{i}", status: "draft", created_at: now, updated_at: now)
          row.update(status: "published", updated_at: Time.now)
        end
      end
    end
    sequel_av_audit_count = @bench_sequel_av_audit_class.count
    sequel_av_revision_count = @bench_sequel_av_revision_class.count

    ar_results = [baseline, active_version, trigger_style]
    ar_baseline = baseline
    puts "[benchmark_group] ActiveRecord comparison"
    ar_results.each do |row|
      ratio_vs_baseline = row[:per_op_median_ms] / ar_baseline[:per_op_median_ms]
      delta_pct = (ratio_vs_baseline - 1.0) * 100.0
      puts format("[benchmark] %-22s rounds=%d median=%8.2fms avg=%8.2fms p95=%8.2fms per-op(p5/mean/p95)=%7.4f/%7.4f/%7.4fms ops/s=%8.1f vs_ar=%6.2fx (%+6.1f%%)",
        row[:label], row[:rounds], row[:median_ms], row[:avg_ms], row[:p95_ms], row[:per_op_p5_ms], row[:per_op_mean_ms], row[:per_op_p95_ms], row[:ops_per_second], ratio_vs_baseline, delta_pct)
    end

    ar_results.each do |row|
      next if row[:label] == ar_baseline[:label]

      overhead_p5 = row[:per_op_p5_ms] - ar_baseline[:per_op_p5_ms]
      overhead_mean = row[:per_op_mean_ms] - ar_baseline[:per_op_mean_ms]
      overhead_p95 = row[:per_op_p95_ms] - ar_baseline[:per_op_p95_ms]
      puts format("[benchmark_overhead] %-22s over_ar_per_record p5/mean/p95=%7.4f/%7.4f/%7.4fms",
        row[:label], overhead_p5, overhead_mean, overhead_p95)
    end

    sequel_results = [sequel_baseline, sequel_av]
    sequel_baseline_row = sequel_baseline
    puts "[benchmark_group] Sequel comparison"
    sequel_results.each do |row|
      ratio_vs_baseline = row[:per_op_median_ms] / sequel_baseline_row[:per_op_median_ms]
      delta_pct = (ratio_vs_baseline - 1.0) * 100.0
      puts format("[benchmark] %-22s rounds=%d median=%8.2fms avg=%8.2fms p95=%8.2fms per-op(p5/mean/p95)=%7.4f/%7.4f/%7.4fms ops/s=%8.1f vs_sequel=%6.2fx (%+6.1f%%)",
        row[:label], row[:rounds], row[:median_ms], row[:avg_ms], row[:p95_ms], row[:per_op_p5_ms], row[:per_op_mean_ms], row[:per_op_p95_ms], row[:ops_per_second], ratio_vs_baseline, delta_pct)
    end

    sequel_overhead_p5 = sequel_av[:per_op_p5_ms] - sequel_baseline_row[:per_op_p5_ms]
    sequel_overhead_mean = sequel_av[:per_op_mean_ms] - sequel_baseline_row[:per_op_mean_ms]
    sequel_overhead_p95 = sequel_av[:per_op_p95_ms] - sequel_baseline_row[:per_op_p95_ms]
    puts format("[benchmark_overhead] %-22s over_sequel_per_record p5/mean/p95=%7.4f/%7.4f/%7.4fms",
      sequel_av[:label], sequel_overhead_p5, sequel_overhead_mean, sequel_overhead_p95)

    all_results = ar_results + sequel_results
    fastest = all_results.min_by { |row| row[:per_op_median_ms] }
    slowest = all_results.max_by { |row| row[:per_op_median_ms] }
    puts format("[benchmark] fastest=%s slowest=%s spread=%0.2fx",
      fastest[:label], slowest[:label], slowest[:per_op_median_ms] / fastest[:per_op_median_ms])

    expect(active_version_audit_count).to eq(ITERATIONS * 2)
    expect(trigger_audit_count).to eq(ITERATIONS * 2)
    expect(sequel_av_audit_count).to eq(ITERATIONS * 2)
    expect(sequel_av_revision_count).to eq(ITERATIONS * 2)
    expect(all_results.all? { |row| row[:median_ms].positive? }).to be(true)
  end
end
