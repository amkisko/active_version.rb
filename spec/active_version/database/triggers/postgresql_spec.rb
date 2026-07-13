require "spec_helper"

RSpec.describe ActiveVersion::Database::Triggers::PostgreSQL do
  describe ".generate_audit_trigger_function" do
    it "builds audit SQL for create, update, and destroy with version and context" do
      sql = described_class.generate_audit_trigger_function(
        "posts",
        "post_audits",
        auditable_type: "Post",
        version_column: "version",
        changes_column: "audited_changes",
        context_column: "audited_context",
        action_column: "action"
      )

      expect(sql).to include("CREATE OR REPLACE FUNCTION active_version_audit_posts()")
      expect(sql).to include("action_type := 'create'")
      expect(sql).to include("action_type := 'update'")
      expect(sql).to include("action_type := 'destroy'")
      expect(sql).to include("current_setting('active_version.context', true)::jsonb")
      expect(sql).to include("auditable_type = 'Post'")
      expect(sql).to include("INSERT INTO post_audits")
      expect(sql).to include("audited_changes")
      expect(sql).to include("audited_context")
    end

    it "defaults auditable_type from table name" do
      sql = described_class.generate_audit_trigger_function("posts", "post_audits")

      expect(sql).to include("auditable_type = 'Post'")
    end
  end

  describe ".generate_audit_trigger" do
    it "creates an AFTER trigger with disable guard" do
      sql = described_class.generate_audit_trigger("posts")

      expect(sql).to include("CREATE TRIGGER active_version_audit_on_posts")
      expect(sql).to include("AFTER INSERT OR UPDATE OR DELETE ON posts")
      expect(sql).to include("active_version.disabled")
      expect(sql).to include("EXECUTE FUNCTION active_version_audit_posts()")
    end
  end

  describe ".generate_revision_trigger_function" do
    it "builds explicit revision column lists from provided columns" do
      sql = described_class.generate_revision_trigger_function(
        "posts",
        "post_revisions",
        foreign_key: "post_id",
        version_column: "version",
        columns: ["id", "title", "body", "created_at", "updated_at"]
      )

      expect(sql).to include("title, body")
      expect(sql).to include("OLD.title, OLD.body")
      expect(sql).not_to include("*,")
      expect(sql).not_to include("OLD.*,")
    end

    it "raises when columns are not provided" do
      expect do
        described_class.generate_revision_trigger_function(
          "posts",
          "post_revisions",
          foreign_key: "post_id",
          version_column: "version"
        )
      end.to raise_error(ArgumentError, /requires :columns option/)
    end
  end
end
