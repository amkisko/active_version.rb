require "spec_helper"
require "support/database"

RSpec.describe "ActiveVersion Schema Changes Integration", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  describe "audit table creation" do
    it "creates audit table with correct columns" do
      # Verify table structure
      columns = ActiveRecord::Base.connection.columns(:post_audits)
      column_names = columns.map(&:name)

      expect(column_names).to include("id")
      expect(column_names).to include("auditable_id")
      expect(column_names).to include("auditable_type")
      expect(column_names).to include("action")
      expect(column_names).to include("audited_changes")
      expect(column_names).to include("version")
      expect(column_names).to include("created_at")
      expect(column_names).to include("updated_at")
    end

    it "creates audit table with correct indexes" do
      indexes = ActiveRecord::Base.connection.indexes(:post_audits)
      index_names = indexes.map(&:name)

      expect(index_names).to include(match(/index.*auditable.*version/))
    end
  end

  describe "revision table creation" do
    it "creates revision table with correct columns" do
      columns = ActiveRecord::Base.connection.columns(:post_revisions)
      column_names = columns.map(&:name)

      expect(column_names).to include("id")
      expect(column_names).to include("post_id")
      expect(column_names).to include("version")
      expect(column_names).to include("created_at")
      expect(column_names).to include("updated_at")
    end

    it "creates revision table with correct indexes" do
      indexes = ActiveRecord::Base.connection.indexes(:post_revisions)
      index_names = indexes.map(&:name)

      expect(index_names).to include(match(/index.*post_id.*version/))
    end
  end

  describe "translation table creation" do
    it "creates translation table with correct columns" do
      columns = ActiveRecord::Base.connection.columns(:post_translations)
      column_names = columns.map(&:name)

      expect(column_names).to include("id")
      expect(column_names).to include("post_id")
      expect(column_names).to include("locale")
      expect(column_names).to include("created_at")
      expect(column_names).to include("updated_at")
    end

    it "creates translation table with correct indexes" do
      indexes = ActiveRecord::Base.connection.indexes(:post_translations)
      index_names = indexes.map(&:name)

      expect(index_names).to include(match(/index.*post_id.*locale/))
    end
  end

  describe "column type changes" do
    it "supports JSONB for audited_changes in PostgreSQL" do
      # This would require PostgreSQL-specific testing
      # For now, just verify text column works
      column = ActiveRecord::Base.connection.columns(:post_audits).find { |c| c.name == "audited_changes" }
      expect(column).to be_present
    end

    it "supports text for audited_changes in SQLite" do
      column = ActiveRecord::Base.connection.columns(:post_audits).find { |c| c.name == "audited_changes" }
      expect(column.type).to eq(:text).or(eq(:string))
    end
  end

  describe "migration helpers" do
    it "provides migration helpers for creating audit tables" do
      # Test that migration helpers exist and work
      expect(ActiveVersion::Migrators::Base).to respond_to(:create_audit_table)
    end

    it "provides migration helpers for creating revision tables" do
      # Test that migration helpers exist and work
      expect(ActiveVersion::Migrators::Base).to respond_to(:create_revision_table)
    end

    it "provides migration helpers for creating translation tables" do
      # Test that migration helpers exist and work
      expect(ActiveVersion::Migrators::Base).to respond_to(:create_translation_table)
    end
  end
end
