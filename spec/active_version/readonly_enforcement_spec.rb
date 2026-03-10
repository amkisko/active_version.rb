require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Readonly Enforcement", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostRevision.destroy_all
    PostAudit.destroy_all
  end

  describe "RevisionRecord readonly enforcement" do
    it "marks persisted revisions as readonly" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!

      revision = post.revisions.first
      expect(revision).to be_present
      expect(revision.readonly?).to be true
    end

    it "prevents updates to persisted revisions" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!

      revision = post.revisions.first
      expect(revision).to be_present
      expect {
        revision.title = "Hacked"
        revision.save!
      }.to raise_error(ActiveVersion::ReadonlyVersionError, /readonly once persisted/)
    end

    it "prevents destroys to persisted revisions" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!

      revision = post.revisions.first
      expect(revision).to be_present
      expect {
        revision.destroy
      }.to raise_error(ActiveVersion::ReadonlyVersionError, /readonly once persisted/)
    end

    it "allows new records to be writable" do
      revision = PostRevision.new(post_id: 1, version: 1, title: "Test")
      expect(revision.readonly?).to be false
      expect(revision).to be_new_record
    end
  end

  describe "AuditRecord readonly enforcement" do
    it "marks persisted audits as readonly" do
      post = Post.create!(title: "Test")

      audit = post.audits.first
      expect(audit.readonly?).to be true
    end

    it "prevents updates to persisted audits" do
      post = Post.create!(title: "Test")

      audit = post.audits.first
      expect(audit).to be_present
      expect {
        audit.action = "hacked"
        audit.save!
      }.to raise_error(ActiveVersion::ReadonlyVersionError)
    end

    it "prevents destroys to persisted audits" do
      post = Post.create!(title: "Test")

      audit = post.audits.first
      expect {
        audit.destroy
      }.to raise_error(ActiveVersion::ReadonlyVersionError, /readonly once persisted/)
    end

    it "allows new records to be writable" do
      post = Post.new(title: "Test")
      audit = PostAudit.new(auditable_type: "Post", auditable_id: 1, action: "create", version: 1)
      expect(audit.readonly?).to be false
      expect(audit).to be_new_record
    end
  end
end
