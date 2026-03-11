require "spec_helper"
require "tmpdir"
require "open3"
require "shellwords"
require "fileutils"

RSpec.describe "ActiveVersion generators end-to-end", type: :integration do
  before do
    if RUBY_ENGINE == "truffleruby"
      skip("generator e2e is skipped on TruffleRuby due to rbs native extension incompatibility under bundle exec in fixture apps")
    end
  end

  before(:all) do
    @tmp_root = Dir.mktmpdir("active_version_generator_e2e")
    @app_path = File.join(@tmp_root, "fixture_app")
  end

  after(:all) do
    FileUtils.rm_rf(@tmp_root) if @tmp_root && Dir.exist?(@tmp_root)
  end

  it "generates files, migrates, and boots with active version runtime smoke checks" do
    run_cmd!(
      %(bundle exec rails new #{shell_escape(@app_path)} \
        --api --skip-bundle --skip-javascript --skip-hotwire --skip-active-job \
        --skip-action-mailer --skip-action-cable --skip-action-mailbox \
        --skip-action-text --skip-active-storage --skip-jbuilder --skip-system-test \
        --skip-bootsnap --database=sqlite3)
    )

    run_cmd_in_app!("bundle exec rails generate model Post title:string body:text --no-test-framework")
    run_cmd_in_app!("bundle exec rails generate active_version:install")
    run_cmd_in_app!("bundle exec rails generate active_version:audits Post --storage=yaml_column")
    run_cmd_in_app!("bundle exec rails generate active_version:revisions Post")
    run_cmd_in_app!("bundle exec rails generate active_version:translations Post --translated-attributes title:string body:text")
    run_cmd_in_app!("bundle exec rails generate active_version:triggers Post --type=audit")

    expect(File).to exist(File.join(@app_path, "config/initializers/active_version.rb"))
    expect(File).to exist(File.join(@app_path, "app/models/post_audit.rb"))
    expect(File).to exist(File.join(@app_path, "app/models/post_revision.rb"))
    expect(File).to exist(File.join(@app_path, "app/models/post_translation.rb"))

    post_model = File.read(File.join(@app_path, "app/models/post.rb"))
    expect(post_model).to include("has_audits")
    expect(post_model).to include("has_revisions")
    expect(post_model).to include("has_translations")

    audit_migration_path = generated_migration_for!("create_post_audits")
    revision_migration_path = generated_migration_for!("create_post_revisions")
    translation_migration_path = generated_migration_for!("create_post_translations")
    trigger_migration_path = generated_migration_for!("add_audit_trigger_to_posts")

    expect(File.read(audit_migration_path)).to include("payload_column_type")
    expect(File.read(audit_migration_path)).not_to include("using: :gin")
    expect(File.read(audit_migration_path)).not_to include("add_index :post_audits, [:auditable_type, :auditable_id],")
    expect(File.read(audit_migration_path)).not_to include("add_index :post_audits, :action")
    expect(File.read(audit_migration_path)).not_to include("add_index :post_audits, :created_at")
    expect(File.read(audit_migration_path)).not_to include("add_index :post_audits, :audited_changes")
    expect(File.read(audit_migration_path)).not_to include("add_index :post_audits, :audited_context")
    expect(File.read(revision_migration_path)).not_to include("add_index :post_revisions, :post_id")
    expect(File.read(revision_migration_path)).not_to include("add_index :post_revisions, :version")
    expect(File.read(revision_migration_path)).to include("create_table :post_revisions")
    expect(File.read(translation_migration_path)).to include("create_table :post_translations")
    trigger_migration = File.read(trigger_migration_path)
    expect(trigger_migration).to include("CREATE OR REPLACE FUNCTION")
    expect(trigger_migration).not_to include("return unless postgresql?")
    expect(trigger_migration).not_to include("def postgresql?")

    # Trigger migrations are PostgreSQL-specific and intentionally fail on SQLite.
    FileUtils.mv(trigger_migration_path, "#{trigger_migration_path}.skip")

    run_cmd_in_app!("bundle exec rails db:migrate")

    smoke_script = <<~RUBY
      raise "missing post_audits" unless ActiveRecord::Base.connection.table_exists?(:post_audits)
      raise "missing post_revisions" unless ActiveRecord::Base.connection.table_exists?(:post_revisions)
      raise "missing post_translations" unless ActiveRecord::Base.connection.table_exists?(:post_translations)

      post = Post.create!(title: "Hello", body: "World")
      post.update!(title: "Updated")

      raise "missing audits association" unless post.respond_to?(:audits)
      raise "missing revisions association" unless post.respond_to?(:revisions)
      raise "missing translations association" unless post.respond_to?(:translations)

      raise "expected at least two audits" unless post.audits.count >= 2
      raise "expected at least one revision" unless post.revisions.count >= 1
      raise "expected default translation" unless post.translations.where(locale: "en").exists?
      raise "translate API failed" unless post.translate(:title, locale: :en)
    RUBY

    run_cmd_in_app!(
      "bundle exec rails runner #{shell_escape(smoke_script)}"
    )
  end

  private

  def shell_escape(value)
    Shellwords.escape(value)
  end

  def run_cmd!(command)
    env = {"RUBYOPT" => [ENV["RUBYOPT"], "-rlogger"].compact.join(" ").strip}
    stdout, stderr, status = Open3.capture3(env, command)
    return stdout if status.success?

    raise <<~MSG
      Command failed: #{command}
      Exit: #{status.exitstatus}
      STDOUT:
      #{stdout}
      STDERR:
      #{stderr}
    MSG
  end

  def run_cmd_in_app!(command)
    env = {
      "RAILS_ENV" => "test",
      "RUBYOPT" => [ENV["RUBYOPT"], "-rlogger"].compact.join(" ").strip,
      "DATABASE_URL" => nil,
      "PGHOST" => nil,
      "PGPORT" => nil,
      "PGDATABASE" => nil,
      "PGUSER" => nil,
      "PGPASSWORD" => nil
    }
    stdout, stderr, status = Open3.capture3(env, command, chdir: @app_path)
    return stdout if status.success?

    raise <<~MSG
      Command failed in #{@app_path}: #{command}
      Exit: #{status.exitstatus}
      STDOUT:
      #{stdout}
      STDERR:
      #{stderr}
    MSG
  end

  def generated_migration_for!(suffix)
    migration = Dir[File.join(@app_path, "db/migrate/*_#{suffix}.rb")].first
    raise "missing migration for #{suffix}" unless migration

    migration
  end
end
