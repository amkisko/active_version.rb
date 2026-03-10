require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Version Enumeration", type: :integration do
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

  describe "#versions" do
    it "returns an enumerator" do
      post = Post.create!(title: "v1")
      expect(post.versions).to be_a(Enumerator)
    end

    it "returns revision instances, not version numbers" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      versions = post.versions.to_a
      expect(versions.length).to eq(2)
      expect(versions.first).to be_a(Post)
      expect(versions.first.title).to eq("v1")
      expect(versions.last.title).to eq("v2")
    end

    it "supports reverse order" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      versions = post.versions(reverse: true).to_a
      expect(versions.length).to eq(2)
      expect(versions.first.title).to eq("v2")
      expect(versions.last.title).to eq("v1")
    end

    it "supports include_self option" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!

      versions = post.versions(include_self: true).to_a
      expect(versions.length).to eq(2)
      expect(versions.last.title).to eq("v2") # Current version
    end

    it "supports enumerator methods" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      # find
      found = post.versions.find { |v| v.title == "v2" }
      expect(found).to be_present
      expect(found.title).to eq("v2")

      # take
      taken = post.versions.take(1)
      expect(taken.length).to eq(1)
      expect(taken.first.title).to eq("v1")

      # select
      selected = post.versions.select { |v| v.title.include?("v") }
      expect(selected.length).to eq(2)
    end

    it "handles empty revisions gracefully" do
      post = Post.create!(title: "v1")
      versions = post.versions.to_a
      expect(versions).to be_empty
    end

    it "lazily loads revisions" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      enum = post.versions
      # Should not load all revisions yet
      expect(enum).to be_a(Enumerator)

      # Only loads when iterated
      first = enum.next
      expect(first.title).to eq("v1")
    end
  end
end
