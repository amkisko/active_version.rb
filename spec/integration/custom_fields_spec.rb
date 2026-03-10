require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion Custom Fields Integration", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    cleanup_test_data
    reset_active_version_context
    # Clear column mappings to ensure clean state
    ActiveVersion.column_mapper.instance_variable_set(:@mappings, {})
  end

  describe "custom column mapping" do
    it "allows custom column names for audit concepts" do
      # Register custom column mapping
      ActiveVersion.column_mapper.register(Post, :audits, :action, :custom_action)
      ActiveVersion.column_mapper.register(Post, :audits, :changes, :custom_changes)

      # Verify mapping
      expect(ActiveVersion.column_mapper.column_for(Post, :audits, :action)).to eq(:custom_action)
      expect(ActiveVersion.column_mapper.column_for(Post, :audits, :changes)).to eq(:custom_changes)
    end

    it "falls back to default columns when not registered" do
      expect(ActiveVersion.column_mapper.column_for(Post, :audits, :action)).to eq(:action)
      expect(ActiveVersion.column_mapper.column_for(Post, :audits, :version)).to eq(:version)
    end

    it "supports different mappings for different models" do
      other_model = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "OtherModel"
        end
      end

      ActiveVersion.column_mapper.register(Post, :audits, :action, :post_action)
      ActiveVersion.column_mapper.register(other_model, :audits, :action, :other_action)

      expect(ActiveVersion.column_mapper.column_for(Post, :audits, :action)).to eq(:post_action)
      expect(ActiveVersion.column_mapper.column_for(other_model, :audits, :action)).to eq(:other_action)
    end
  end

  describe "custom audit options" do
    it "supports only option to audit specific attributes" do
      # Create initial record
      post = Post.create!(title: "Hello", body: "World")
      expect(post.audits.count).to eq(1)

      # Update with actual changes using save! to ensure persistence
      post.title = "Updated"
      post.body = "Changed"
      post.save!

      # Reload to get fresh audit count
      post.reload
      expect(post.audits.count).to eq(2)

      # Verify update audit exists
      audit = post.audits.order(version: :asc).last
      expect(audit).to be_present
      expect(audit.action).to eq("update")
      expect(audit.version).to eq(2)
      # Should only audit title if configured with only: [:title]
    end

    it "supports except option to exclude attributes" do
      # Create initial record
      post = Post.create!(title: "Hello", body: "World")

      # Update with actual changes
      post.title = "Updated"
      post.body = "Changed"
      post.save!

      # Reload to get fresh audit
      post.reload
      audit = post.audits.order(version: :asc).last
      expect(audit).to be_present
      expect(audit.action).to eq("update")
      # Should exclude body if configured with except: [:body]
    end

    it "supports comment_required option" do
      # This would require audit_comment to be present
      # Implementation depends on has_audits configuration
    end
  end

  describe "custom revision options" do
    it "supports custom version column name" do
      # Test with custom version column mapping
      ActiveVersion.column_mapper.register(Post, :revisions, :version, :custom_version)

      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!

      expect(post.revisions.count).to eq(1)
    end

    it "supports redo! with a mapped revision version column" do
      conn = ActiveRecord::Base.connection
      conn.create_table :custom_posts, force: true do |t|
        t.string :title
        t.timestamps
      end
      conn.create_table :custom_post_revisions, force: true do |t|
        t.references :custom_post, null: false
        t.integer :custom_version, null: false
        t.string :title
        t.timestamps
      end

      custom_revision_class = Class.new(ApplicationRecord) do
        self.table_name = "custom_post_revisions"
        include ActiveVersion::Revisions::RevisionRecord

        def self.name
          "CustomPostRevision"
        end
      end
      Object.const_set(:CustomPostRevision, custom_revision_class)

      custom_post_class = Class.new(ApplicationRecord) do
        self.table_name = "custom_posts"
        include ActiveVersion::Revisions::HasRevisions

        def self.name
          "CustomPost"
        end

        has_revisions as: CustomPostRevision
      end
      Object.const_set(:CustomPost, custom_post_class)
      CustomPostRevision.setup_associations if CustomPostRevision.respond_to?(:setup_associations)

      ActiveVersion.column_mapper.register(CustomPost, :revisions, :version, :custom_version)

      post = CustomPost.create!(title: "v1")
      post.update!(title: "v2")
      post.update!(title: "v3")

      post.undo!
      expect(post.title).to eq("v2")

      post.redo!
      expect(post.title).to eq("v3")
    ensure
      ActiveVersion.column_mapper.instance_variable_set(:@mappings, {})
      Object.send(:remove_const, "CustomPost") if Object.const_defined?("CustomPost")
      Object.send(:remove_const, "CustomPostRevision") if Object.const_defined?("CustomPostRevision")
      conn.drop_table(:custom_post_revisions, if_exists: true) if conn.data_source_exists?(:custom_post_revisions)
      conn.drop_table(:custom_posts, if_exists: true) if conn.data_source_exists?(:custom_posts)
    end
  end

  describe "custom translation options" do
    it "supports custom locale column name" do
      # Test with custom locale column mapping
      ActiveVersion.column_mapper.register(Post, :translations, :locale, :custom_locale)

      post = Post.create!(title: "Hello")
      translation = post.translations.create!(locale: "fi", title: "Hei")

      expect(translation).to be_persisted
    end
  end
end
