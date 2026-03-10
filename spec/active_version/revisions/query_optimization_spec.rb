require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Query Optimization", type: :integration do
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

  describe "refreshable_column_names" do
    it "identifies columns with default functions" do
      post = Post.create!(title: "Test")

      # Mock columns with default functions
      allow(post.class).to receive(:columns).and_return([
        double(name: "id", default_function: nil),
        double(name: "title", default_function: nil),
        double(name: "created_at", default_function: "NOW()"),
        double(name: "updated_at", default_function: "NOW()")
      ])

      refreshable = post.send(:refreshable_column_names)
      expect(refreshable).to include("created_at", "updated_at")
      expect(refreshable).not_to include("id", "title")
    end

    it "excludes primary key from refreshable columns" do
      post = Post.create!(title: "Test")

      allow(post.class).to receive_messages(primary_key: "id", columns: [
        double(name: "id", default_function: "nextval()")
      ])

      refreshable = post.send(:refreshable_column_names)
      expect(refreshable).not_to include("id")
    end
  end

  describe "snapshot creation with refreshable columns" do
    it "refreshes only columns with default functions" do
      post = Post.create!(title: "Test")

      # Mock refreshable columns
      allow(post).to receive(:refreshable_column_names).and_return(["updated_at"])
      allow(post.class).to receive(:select).and_return(post.class)
      allow(post.class).to receive(:find).with(post.id).and_return(
        double(updated_at: 1.hour.from_now)
      )

      snapshot = post.create_snapshot!
      expect(snapshot).to be_present
    end

    it "handles empty refreshable columns gracefully" do
      post = Post.create!(title: "Test")

      allow(post).to receive(:refreshable_column_names).and_return([])

      snapshot = post.create_snapshot!
      expect(snapshot).to be_present
    end
  end
end
