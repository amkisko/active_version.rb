require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Snapshot Enhancements", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostRevision.destroy_all
  end

  describe "create_snapshot! with only option" do
    it "creates snapshot with only specified attributes" do
      post = Post.create!(title: "v1", body: "Body")
      post.title = "v2"
      post.save!

      snapshot = post.create_snapshot!(only: [:title])
      expect(snapshot.title).to eq("v2")
      expect(snapshot.body).to be_nil
    end

    it "excludes other attributes when using only" do
      post = Post.create!(title: "v1", body: "Body")
      snapshot = post.create_snapshot!(only: [:title])

      expect(snapshot.attributes.keys).to include("title")
      expect(snapshot.attributes.keys).not_to include("body")
    end
  end

  describe "create_snapshot! with except option" do
    it "creates snapshot excluding specified attributes" do
      post = Post.create!(title: "v1", body: "Body")
      post.title = "v2"
      post.save!

      snapshot = post.create_snapshot!(except: [:body])
      expect(snapshot.title).to eq("v2")
      expect(snapshot.body).to be_nil
    end

    it "includes other attributes when using except" do
      post = Post.create!(title: "v1", body: "Body")
      snapshot = post.create_snapshot!(except: [:body])

      expect(snapshot.attributes.keys).to include("title")
      expect(snapshot.attributes.keys).not_to include("body")
    end
  end

  describe "create_snapshot! with timestamp option" do
    it "uses provided timestamp" do
      post = Post.create!(title: "v1")
      custom_time = 1.day.ago

      snapshot = post.create_snapshot!(timestamp: custom_time)
      expect(snapshot.created_at).to be_within(1.second).of(custom_time)
    end

    it "defaults to current time" do
      post = Post.create!(title: "v1")
      before = Time.current

      snapshot = post.create_snapshot!
      after = Time.current

      expect(snapshot.created_at).to be_between(before, after)
    end
  end

  describe "create_snapshots class method enhancements" do
    it "supports only_missing option" do
      post1 = Post.create!(title: "v1")
      post1.title = "v2"
      post1.save! # Has revision

      post2 = Post.create!(title: "v1") # No revision

      Post.create_snapshots(only_missing: true)

      expect(post1.revisions.count).to eq(1) # Unchanged
      expect(post2.revisions.count).to eq(1) # Created
    end

    it "creates snapshots for all records" do
      post1 = Post.create!(title: "v1")
      post2 = Post.create!(title: "v2")

      Post.create_snapshots

      expect(post1.revisions.count).to eq(1)
      expect(post2.revisions.count).to eq(1)
    end
  end
end
