require "spec_helper"

RSpec.describe ActiveVersion::Database::Triggers::PostgreSQL do
  describe ".generate_revision_trigger_function" do
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
