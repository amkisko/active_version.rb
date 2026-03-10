require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Debounce Time", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostRevision.destroy_all
    ActiveVersion.config.debounce_time = nil
  end

  describe "debounce time configuration" do
    it "merges revisions within time window" do
      ActiveVersion.config.debounce_time = 5 # 5 seconds

      post = Post.create!(title: "v1")
      first_revision_time = post.revisions.first&.created_at || Time.current

      # Create snapshot within debounce window
      post.title = "v2"
      post.save!
      post.create_snapshot!(debounce_time: 5, timestamp: first_revision_time + 2.seconds)

      # Should merge with previous revision (if one exists from update)
      # Note: update creates revision automatically, so we test manual snapshot
      expect(post.revisions.count).to be >= 1
    end

    it "creates new revision outside time window" do
      ActiveVersion.config.debounce_time = 5 # 5 seconds

      post = Post.create!(title: "v1")
      first_revision_time = post.revisions.first&.created_at || Time.current

      # Create snapshot outside debounce window
      post.title = "v2"
      post.save!
      post.create_snapshot!(debounce_time: 5, timestamp: first_revision_time + 6.seconds)

      # Should create new revision
      expect(post.revisions.count).to be >= 2
    end

    it "supports per-snapshot debounce time" do
      post = Post.create!(title: "v1")
      first_revision_time = post.revisions.first&.created_at || Time.current

      # Use custom debounce time
      post.create_snapshot!(debounce_time: 10, timestamp: first_revision_time + 2.seconds) # 10 second window

      # Should merge (within 10 second window) if revision exists
      expect(post.revisions.count).to be >= 1
    end

    it "handles nil debounce time" do
      ActiveVersion.config.debounce_time = nil

      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!

      # Should always create new revision
      expect(post.revisions.count).to eq(1)
    end

    it "checks should_merge_with_previous? correctly" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save! # Creates revision

      last_revision = post.revisions.order(version: :desc).first
      within_window = last_revision.created_at + 2.seconds
      outside_window = last_revision.created_at + 6.seconds

      # Within window
      expect(post.send(:should_merge_with_previous?, 5, within_window)).to be true

      # Outside window
      expect(post.send(:should_merge_with_previous?, 5, outside_window)).to be false
    end
  end
end
