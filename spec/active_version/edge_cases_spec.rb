require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Edge Cases", type: :integration do
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
    ActiveVersion.config.return_self_if_no_revisions = false
  end

  describe "nil/empty revision data handling" do
    it "returns nil when no revisions exist" do
      post = Post.create!(title: "Test")
      expect(post.at(version: 1)).to be_nil
    end

    it "returns self when return_self_if_no_revisions is true" do
      ActiveVersion.config.return_self_if_no_revisions = true
      post = Post.create!(title: "Test")
      expect(post.at(version: 1)).to eq(post)
    end

    it "handles empty revisions gracefully" do
      post = Post.create!(title: "Test")
      versions = post.versions.to_a
      expect(versions).to be_empty
    end
  end

  describe "deleted column handling" do
    it "filters out deleted columns from snapshots" do
      post = Post.create!(title: "v1", body: "Body")
      post.title = "v2"
      post.save!

      # Simulate column deletion by removing from attributes
      revision = post.revisions.first
      revision.instance_variable_set(:@attributes, revision.attributes.except("body"))

      # Should not raise error when accessing revision
      expect { post.at(version: 1) }.not_to raise_error
    end

    it "handles deleted columns in diff_from" do
      post = Post.create!(title: "v1", body: "Body")
      post.title = "v2"
      post.save!

      # Should not include deleted columns in diff
      diff = post.diff_from(version: 1)
      expect(diff["changes"]).to have_key("title")
    end
  end

  describe "future time validation" do
    it "raises error when querying future time" do
      post = Post.create!(title: "Test")
      future_time = 1.day.from_now

      expect {
        post.revision_at(time: future_time)
      }.to raise_error(ActiveVersion::FutureTimeError, /Future state cannot be known/)
    end

    it "raises error in at method for future time" do
      post = Post.create!(title: "Test")
      future_time = 1.day.from_now

      unless ActiveVersion.config.return_self_if_no_revisions
        expect {
          post.at(time: future_time)
        }.to raise_error(ActiveVersion::FutureTimeError)
      end
    end

    it "allows past and present times" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!

      past_time = 1.hour.ago
      revision = post.revision_at(time: past_time)
      expect(revision).to be_present
    end
  end

  describe "transaction rollback handling" do
    it "clears audit association cache on rollback" do
      post = Post.create!(title: "Test")

      ActiveRecord::Base.transaction do
        post.title = "Updated"
        post.save!
        expect(post.audits.count).to eq(2)
        raise ActiveRecord::Rollback
      end

      # Association should be cleared
      post.reload
      expect(post.audits.count).to eq(1) # Only create audit
    end

    it "clears revision association cache on rollback" do
      post = Post.create!(title: "Test")

      ActiveRecord::Base.transaction do
        post.title = "Updated"
        post.save!
        expect(post.revisions.count).to eq(1)
        raise ActiveRecord::Rollback
      end

      # Association should be cleared
      post.reload
      expect(post.revisions.count).to eq(0)
    end
  end

  describe "association proxy cleanup" do
    it "clears association proxies in revision_with" do
      post = Post.create!(title: "Test", body: "Body")
      post.title = "Updated"
      post.save!

      audit = post.audits.last
      revision = post.audit_revision(version: 2)

      # Should not have stale association references
      expect(revision.instance_variables.none? { |ivar|
        proxy = revision.instance_variable_get(ivar)
        proxy.respond_to?(:proxy_respond_to?) && !proxy.nil?
      }).to be true
    end
  end
end
