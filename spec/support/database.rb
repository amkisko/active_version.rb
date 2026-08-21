require "active_record"

SpecTestLogging.silence! if defined?(SpecTestLogging)

# Database setup for integration tests
module DatabaseHelper
  TEST_TABLES = %w[post_audits post_revisions post_translations posts].freeze

  def self.setup
    SpecTestLogging.silence! if defined?(SpecTestLogging)
    establish_test_connection
    assert_polyrun_database!
    define_schema unless required_tables_exist?
    empty_test_tables
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
    return database_url if database_url&.match?(/\Apostgres(?:ql)?:\/\//)

    {
      adapter: "postgresql",
      host: ENV.fetch("PGHOST", "localhost"),
      port: ENV.fetch("PGPORT", 5432),
      database: shard_database_name,
      username: ENV.fetch("PGUSER", "postgres"),
      password: ENV["PGPASSWORD"]
    }
  end

  def self.postgresql_explicitly_requested?
    database_url = ENV["DATABASE_URL"]
    return true if database_url&.match?(/\Apostgres(?:ql)?:\/\//)

    ENV.key?("TEST_DB_NAME") || ENV.key?("PGHOST") || ENV.key?("PGPORT") || ENV.key?("PGDATABASE") || ENV.key?("PGUSER")
  end

  def self.shard_database_name
    name = ENV["TEST_DB_NAME"].to_s
    return name unless name.empty?

    ENV.fetch("PGDATABASE", "active_version_test")
  end

  def self.assert_polyrun_database!
    expected = ENV["TEST_DB_NAME"].to_s
    return if expected.empty?
    return unless postgres_adapter?

    actual = ActiveRecord::Base.connection.current_database
    return if actual == expected

    raise "DatabaseHelper connected to #{actual.inspect}; polyrun TEST_DB_NAME is #{expected.inspect}"
  end

  def self.postgres_adapter?
    ActiveRecord::Base.connection.adapter_name.match?(/postgres/i)
  end

  def self.required_tables_exist?
    connection = ActiveRecord::Base.connection
    TEST_TABLES.all? { |table_name| connection.table_exists?(table_name) }
  end

  def self.empty_test_tables
    connection = ActiveRecord::Base.connection
    present = TEST_TABLES.select { |table_name| connection.table_exists?(table_name) }
    return if present.empty?

    if postgres_adapter?
      connection.execute("TRUNCATE TABLE #{present.join(", ")} RESTART IDENTITY CASCADE")
    else
      present.each { |table_name| connection.execute("DELETE FROM #{table_name}") }
    end
  end

  def self.define_schema
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
        t.text :audited_changes
        t.integer :version, null: false
        t.references :user, polymorphic: true
        t.text :comment
        t.text :audited_context
        t.string :remote_address
        t.string :request_uuid
        t.timestamps
      end

      add_index :post_translations, [:post_id, :locale], unique: true
      add_index :post_revisions, [:post_id, :version], unique: true
      add_index :post_audits, [:auditable_type, :auditable_id, :version], unique: true, name: "index_post_audits_on_auditable_and_version"
    end
  end
end
