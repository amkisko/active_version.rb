require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion Revisions Integration", type: :integration do
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

  describe "basic revision functionality" do
    it "creates a revision on update" do
      post = Post.create!(title: "v1", body: "First version")
      expect(post.revisions.count).to eq(0)
      expect(post.current_version).to eq(0)

      post.title = "v2"
      post.body = "Second version"
      post.save!
      expect(post.revisions.count).to eq(1)
      expect(post.current_version).to eq(1)

      revision = post.revisions.first
      expect(revision.version).to eq(1)
      expect(revision.title).to eq("v1") # Old value
    end

    it "retrieves revision at specific version" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      revision = post.revision(version: 1)
      expect(revision).to be_present
      expect(revision.title).to eq("v1")

      revision = post.revision(version: 2)
      expect(revision).to be_present
      expect(revision.title).to eq("v2")
    end

    it "creates snapshot manually" do
      post = Post.create!(title: "v1", body: "First")
      post.title = "v2"
      post.body = "Second"
      post.save!

      snapshot = post.create_snapshot!
      expect(snapshot.version).to eq(2)
      expect(snapshot.title).to eq("v2")
      expect(post.current_version).to eq(2)
    end

    it "reverts to specific version" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      result = post.revert_to(version: 1)
      expect(result).to be true
      expect(post.title).to eq("v1")
      expect(post.revisions.count).to eq(3) # Original + revert creates new revision
    end

    it "enumerates versions as revision instances" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      versions = post.versions.to_a
      expect(versions.length).to eq(2) # v1 and v2 (not including current)
      expect(versions.first).to be_a(Post)
      expect(versions.first.title).to eq("v1")
      expect(versions.last.title).to eq("v2")
    end

    it "supports include_self option" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!

      versions = post.versions(include_self: true).to_a
      expect(versions.length).to eq(2) # v1 and current
      expect(versions.last.title).to eq("v2") # Current version
    end

    it "supports reverse order" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      versions = post.versions(reverse: true).to_a
      expect(versions.first.title).to eq("v2")
      expect(versions.last.title).to eq("v1")
    end
  end

  describe "revision scopes" do
    it "finds latest revision" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      latest = post.revisions.latest.first
      expect(latest.version).to eq(2)
      expect(latest.title).to eq("v2")
    end

    it "finds revision at specific version" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      revision = post.revisions.at_version(1).first
      expect(revision).to be_present
      expect(revision.title).to eq("v1")
    end
  end

  describe "complex undo/redo lifecycle flow" do
    it "handles create/update/undo/redo/destroy sequence deterministically" do
      post = Post.create!(title: "v1")
      post.update!(title: "v2")
      post.update!(title: "v3")

      expect(post.undo!).to be true
      expect(post.title).to eq("v2")

      expect(post.undo!).to be true
      expect(post.title).to eq("v1")

      post.update!(title: "v4")
      expect(post.undo!).to be true
      expect(post.title).to eq("v1")

      expect(post.undo!).to be false
      expect(post.title).to eq("v1")

      expect(post.redo!).to be true
      expect(post.title).to eq("v4")

      post.update!(title: "v5")
      post.destroy!

      expect(post.undo!).to be false
    end
  end
end
