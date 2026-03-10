require "spec_helper"

RSpec.describe ActiveVersion::Revisions::RevisionRecord do
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :posts, force: true do |t|
        t.string :title
        t.timestamps
      end

      create_table :post_revisions, force: true do |t|
        t.references :post, null: false, foreign_key: true
        t.integer :version, null: false
        t.string :title
        t.timestamps
      end

      add_index :post_revisions, [:post_id, :version], unique: true
    end
  end

  let(:source_class) do
    Class.new(ApplicationRecord) do
      self.table_name = "posts"
      def self.name
        "Post"
      end
    end
  end

  let(:revision_class) do
    Class.new(ApplicationRecord) do
      include ActiveVersion::Revisions::RevisionRecord

      self.table_name = "post_revisions"
      def self.name
        "PostRevision"
      end
    end
  end

  describe ".revision_record?" do
    it "returns true" do
      expect(revision_class.revision_record?).to be true
    end
  end

  describe ".source_name" do
    it "extracts source name from class name" do
      expect(revision_class.source_name).to eq(:post)
    end
  end

  describe ".source_foreign_key" do
    it "returns the foreign key name" do
      expect(revision_class.source_foreign_key).to eq("post_id")
    end
  end

  describe "configuration DSL" do
    it "supports keyword arguments" do
      revision_class.configure_revision(version_column: :revision_no, foreign_key: :post_uuid)

      expect(revision_class.revision_column_for(:version)).to eq(:revision_no)
      expect(revision_class.source_foreign_key).to eq("post_uuid")
    end

    it "supports block configuration" do
      revision_class.configure_revision do
        version_column :rev
        foreign_key [:tenant_id, :post_id]
        identity_resolver [:tenant_id, :id]
      end

      expect(revision_class.revision_column_for(:version)).to eq(:rev)
      expect(revision_class.source_foreign_key).to eq(%w[tenant_id post_id])
      expect(revision_class.source_primary_key).to eq(%w[tenant_id id])
    end
  end

  describe ".latest" do
    it "defines latest scope" do
      expect(revision_class).to respond_to(:latest)
    end
  end

  describe ".at_version" do
    it "defines at_version scope" do
      expect(revision_class).to respond_to(:at_version)
    end
  end

  describe "#source" do
    let(:revision) { revision_class.new }

    it "responds to source method" do
      expect(revision).to respond_to(:source)
    end
  end
end
