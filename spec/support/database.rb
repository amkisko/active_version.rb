require "active_record"

# Database setup for integration tests
module DatabaseHelper
  def self.setup
    establish_test_connection

    # Create tables
    ActiveRecord::Schema.define do
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
    ActiveRecord::Base.establish_connection(adapter: "postgresql")
    ActiveRecord::Base.connection.execute("SELECT 1")
  rescue
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )
  end
end
