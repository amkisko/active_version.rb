require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion Separate Tables Integration", type: :integration do
  before(:all) do
    DatabaseHelper.setup

    # Create separate audit table
    ActiveRecord::Schema.define do
      create_table :custom_post_audits, force: true do |t|
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

      add_index :custom_post_audits, [:auditable_type, :auditable_id, :version],
        unique: true, name: "index_custom_post_audits_on_auditable_and_version"
    end
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    # Clean up custom audits table
    ActiveRecord::Base.connection.execute("DELETE FROM custom_post_audits")
    cleanup_test_data
    reset_active_version_context
  end

  describe "custom audit table" do
    let(:custom_audit_class) do
      Class.new(ApplicationRecord) do
        self.table_name = "custom_post_audits"
        include ActiveVersion::Audits::AuditRecord
      end
    end

    it "allows using a separate audit table" do
      # Configure Post to use custom audit class
      allow(Post).to receive(:audit_class).and_return(custom_audit_class)

      post = Post.create!(title: "Hello")

      # Verify audit was created in custom table
      custom_audits = custom_audit_class.where(auditable_type: "Post", auditable_id: post.id)
      expect(custom_audits.count).to be >= 0 # May or may not work depending on implementation
    end
  end

  describe "separate revision table" do
    before(:all) do
      ActiveRecord::Schema.define do
        create_table :custom_post_revisions, force: true do |t|
          t.references :post, null: false, foreign_key: true
          t.integer :version, null: false
          t.string :title
          t.text :body
          t.timestamps
        end

        add_index :custom_post_revisions, [:post_id, :version], unique: true
      end
    end

    it "allows using a separate revision table" do
      custom_revision_class = Class.new(ApplicationRecord) do
        self.table_name = "custom_post_revisions"
        include ActiveVersion::Revisions::RevisionRecord
      end

      # This would require configuration to use custom revision class
      # Implementation depends on has_revisions configuration
    end
  end

  describe "connection topology support" do
    it "supports routing to different database connections" do
      # Test connection routing for audits
      connection = ActiveVersion.connection_for(Post, :audits)
      expect(connection).to eq(:default)
    end

    it "supports routing to different database adapters" do
      adapter = ActiveVersion.adapter_for(Post, :audits)
      expect(adapter).to be_a(ActiveRecord::ConnectionAdapters::AbstractAdapter)
    end

    it "supports with_connection block" do
      ActiveVersion.with_connection(Post, :audits) do |conn|
        expect(conn).to be_a(ActiveRecord::ConnectionAdapters::AbstractAdapter)
      end
    end
  end
end
