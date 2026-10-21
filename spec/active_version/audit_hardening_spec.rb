require "spec_helper"
require "support/database"
require "support/models"
require "active_support/testing/time_helpers"

RSpec.describe "ActiveVersion audit hardening", type: :integration do
  include ActiveSupport::Testing::TimeHelpers

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
    ActiveVersion.clear_context!
    ActiveVersion.config.debounce_time = nil
    ActiveVersion.config.auditing_enabled = true
  end

  after do
    ActiveVersion.clear_context!
    ActiveVersion.config.debounce_time = nil
    ActiveVersion.config.auditing_enabled = true
  end

  describe "without_auditing isolation" do
    it "keeps the process config enabled while the block runs" do
      expect(ActiveVersion.config.auditing_enabled).to be true

      ActiveVersion.without_auditing do
        expect(ActiveVersion.auditing_enabled).to be false
        expect(ActiveVersion.config.auditing_enabled).to be true
      end

      expect(ActiveVersion.auditing_enabled).to be true
    end

    it "does not silence audits on another thread" do
      barrier = Queue.new
      release = Queue.new
      other_audit_count = nil

      thread = Thread.new do
        barrier.pop
        post = Post.create!(title: "other-thread")
        post.update!(title: "other-thread-updated")
        other_audit_count = post.audits.count
        release.push(true)
      end

      ActiveVersion.without_auditing do
        barrier.push(true)
        release.pop
        silenced = Post.create!(title: "silenced")
        silenced.update!(title: "still-silenced")
        expect(silenced.audits.count).to eq(0)
      end

      thread.join
      expect(other_audit_count).to be >= 1
    end
  end

  describe "context restore" do
    it "does not copy persistent keys into request store on with_context exit" do
      ActiveVersion.with_context!({user: 1})
      ActiveVersion.with_context({ip: "10.0.0.1"}) {}

      ActiveVersion.with_context!({user: 2})
      expect(ActiveVersion.context[:user]).to eq(2)
    end

    it "honors transactional: false by skipping transactional context path" do
      allow(ActiveVersion).to receive(:transactional_context_supported?).and_return(true)
      expect(ActiveVersion).not_to receive(:with_transactional_context)

      ActiveVersion.with_context({ip: "127.0.0.1"}, transactional: false) do
        expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")
      end
    end
  end

  describe "revision at(time:)" do
    it "returns the live state between updates, not the previous pre-state" do
      travel_to Time.utc(2026, 1, 1, 12, 0, 0) do
        post = Post.create!(title: "A")
      end

      travel_to Time.utc(2026, 1, 1, 12, 0, 10) do
        post = Post.find_by!(title: "A")
        post.update!(title: "B")
      end

      travel_to Time.utc(2026, 1, 1, 12, 0, 20) do
        post = Post.find_by!(title: "B")
        post.update!(title: "C")
      end

      post = Post.find_by!(title: "C")
      mid = Time.utc(2026, 1, 1, 12, 0, 15)
      at_mid = post.at(time: mid)
      expect(at_mid).not_to be_nil
      expect(at_mid.title).to eq("B")
    end
  end

  describe "debounce merge" do
    it "keeps the earliest pre-change state when updates land inside the window" do
      ActiveVersion.config.debounce_time = 30

      post = Post.create!(title: "A")
      post.update!(title: "B")
      first_revision = post.revisions.order(:version).first
      expect(first_revision.title).to eq("A")

      post.update!(title: "C")
      expect(post.revisions.count).to eq(1)
      expect(post.revisions.order(:version).first.title).to eq("A")
    end
  end
end
