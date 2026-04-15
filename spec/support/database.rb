require "active_record"

SpecTestLogging.silence! if defined?(SpecTestLogging)

# Database setup for integration tests
module DatabaseHelper
  def self.setup
    SpecTestLogging.silence! if defined?(SpecTestLogging)
    establish_test_connection

    # Create tables
    ActiveRecord::Schema.define(verbose: false) do
      create_table :posts, force: :cascade do |t|
        t.string :title
        t.text :body
        t.string :status
        t.timestamps
      end

      create_table :post_translations, force: :cascade do |t|
        t.references :post, null: false, foreign_key: true
        t.string :locale, null: false
        t.string :title
        t.text :body
        t.timestamps
      end

      create_table :post_revisions, force: :cascade do |t|
        t.references :post, null: false, foreign_key: true
        t.integer :version, null: false
        t.string :title
        t.text :body
        t.string :status
        t.timestamps
      end

      create_table :post_audits, force: :cascade do |t|
        t.references :auditable, polymorphic: true, null: false
        t.string :action, null: false
        t.text :audited_changes # Use text for SQLite compatibility, JSONB for PostgreSQL
        t.integer :version, null: false
        t.references :user, polymorphic: true
        t.text :comment
        t.text :audited_context # Use text for SQLite compatibility
        t.string :remote_address
        t.string :request_uuid
        t.timestamps
      end

      add_index :post_translations, [:post_id, :locale], unique: true
      add_index :post_revisions, [:post_id, :version], unique: true
      add_index :post_audits, [:auditable_type, :auditable_id, :version], unique: true, name: "index_post_audits_on_auditable_and_version"
    end
  end

  def self.teardown
    ActiveRecord::Base.connection.close
  end

  def self.establish_test_connection
    # Prefer PostgreSQL when available so PostgreSQL-specific integration
    # examples execute in normal suite runs.
    ActiveRecord::Base.establish_connection(postgresql_connection_config)
    ActiveRecord::Base.connection.execute("SELECT 1")
  rescue
    raise if postgresql_explicitly_requested?

    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )
  end

  def self.postgresql_connection_config
    database_url = ENV["DATABASE_URL"]
    # +polyrun run-shards+ may already set DATABASE_URL to the shard DB; +polyrun env+ (CI matrix / ci-shard-rspec)
    # does not — only add _{idx} when missing, so we never double-suffix (e.g. _0_0).
    if database_url&.match?(/\Apostgres(?:ql)?:\/\//) && ENV["POLYRUN_SHARD_TOTAL"].to_i > 1
      idx = Integer(ENV.fetch("POLYRUN_SHARD_INDEX", "0"), exception: false)
      idx = 0 if idx.nil?
      if (m = database_url.match(%r{/([^/?]+)(\?|$)})) && !m[1].end_with?("_#{idx}")
        begin
          require "polyrun"
          database_url = Polyrun::Database::Shard.database_url_with_shard(database_url, idx)
        rescue LoadError
          # polyrun optional for contributors without the gem
        end
      end
    end
    return database_url if database_url&.match?(/\Apostgres(?:ql)?:\/\//)

    {
      adapter: "postgresql",
      host: ENV.fetch("PGHOST", "localhost"),
      port: ENV.fetch("PGPORT", 5432),
      database: ENV.fetch("PGDATABASE", "active_version_test"),
      username: ENV.fetch("PGUSER", "postgres"),
      password: ENV["PGPASSWORD"]
    }
  end

  def self.postgresql_explicitly_requested?
    database_url = ENV["DATABASE_URL"]
    return true if database_url&.match?(/\Apostgres(?:ql)?:\/\//)

    ENV.key?("PGHOST") || ENV.key?("PGPORT") || ENV.key?("PGDATABASE") || ENV.key?("PGUSER")
  end
end
