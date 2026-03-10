require "spec_helper"
require "support/database"
require "support/integration_helpers"

RSpec.describe "Table storage audits without audited_changes column", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    cleanup_test_data
    reset_active_version_context
  end

  it "auto-detects table storage from audit schema and infers audited columns" do
    conn = ActiveRecord::Base.connection
    conn.create_table :column_audit_posts, force: true do |t|
      t.string :title, null: false
      t.text :body
      t.text :internal_notes
      t.boolean :published, null: false, default: false
      t.timestamps
    end

    conn.create_table :column_audit_post_audits, force: true do |t|
      t.references :auditable, polymorphic: true, null: false
      t.string :action, null: false
      t.integer :version, null: false
      t.text :comment
      t.text :audited_context
      t.string :request_uuid
      t.string :remote_address
      t.string :title
      t.boolean :published
      t.timestamps
    end

    column_audit_class = Class.new(ApplicationRecord) do
      self.table_name = "column_audit_post_audits"
      include ActiveVersion::Audits::AuditRecord

      def self.name
        "ColumnAuditPostAudit"
      end
    end
    Object.const_set("ColumnAuditPostAudit", column_audit_class)

    column_post_class = Class.new(ApplicationRecord) do
      self.table_name = "column_audit_posts"
      include ActiveVersion::Audits::HasAudits

      def self.name
        "ColumnAuditPost"
      end

      has_audits as: ColumnAuditPostAudit
    end
    Object.const_set("ColumnAuditPost", column_post_class)
    ColumnAuditPostAudit.setup_associations if ColumnAuditPostAudit.respond_to?(:setup_associations)

    post = ColumnAuditPost.create!(
      title: "v1",
      body: "body",
      internal_notes: "private",
      published: false
    )
    expect(post.audits.count).to eq(1)
    expect(ColumnAuditPostAudit.column_names).not_to include("audited_changes")
    expect(post.audits.last.title).to eq("v1")
    expect(post.audits.last.published).to eq(false)

    # This field is excluded from auditing because destination audit schema
    # does not contain it, so inferred table columns drive auditing.
    post.update!(internal_notes: "private-2")
    expect(post.audits.count).to eq(1)

    post.update!(title: "v2", published: true)
    latest = post.audits.order(version: :desc).first
    expect(latest.title).to eq("v2")
    expect(latest.published).to eq(true)

    # Filtering directly on audit record columns.
    expect(ColumnAuditPostAudit.where(title: "v2", published: true).count).to eq(1)
  ensure
    Object.send(:remove_const, "ColumnAuditPost") if Object.const_defined?("ColumnAuditPost")
    Object.send(:remove_const, "ColumnAuditPostAudit") if Object.const_defined?("ColumnAuditPostAudit")
    conn.drop_table(:column_audit_post_audits, if_exists: true) if conn.data_source_exists?(:column_audit_post_audits)
    conn.drop_table(:column_audit_posts, if_exists: true) if conn.data_source_exists?(:column_audit_posts)
  end
end
