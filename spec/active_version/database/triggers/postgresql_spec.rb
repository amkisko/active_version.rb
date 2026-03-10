require "spec_helper"

RSpec.describe ActiveVersion::Database::Triggers::PostgreSQL do
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
