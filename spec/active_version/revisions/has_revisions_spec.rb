require "spec_helper"
require "support/models"

RSpec.describe ActiveVersion::Revisions::HasRevisions do
  before(:all) do
    DatabaseHelper.setup
  end

  let(:model_class) do
    # Use a class that has the revision class available
    Post
  end

  describe ".revision_record?" do
    it "returns false" do
      expect(model_class.revision_record?).to be false
    end
  end

  describe ".revision_class" do
    it "returns the revision class" do
      expect(model_class.revision_class).to eq(PostRevision)
    end
  end

  describe ".revision_class_name" do
    it "returns the revision class name" do
      expect(model_class.revision_class_name).to eq("PostRevision")
    end
  end

  describe ".create_snapshots" do
    it "defines create_snapshots class method" do
      expect(model_class).to respond_to(:create_snapshots)
    end
  end

  describe "#revision" do
    let(:instance) { model_class.new }

    it "responds to revision method" do
      expect(instance).to respond_to(:revision)
    end
  end

  describe "#revision_at" do
    let(:instance) { model_class.new }

    it "responds to revision_at method" do
      expect(instance).to respond_to(:revision_at)
    end
  end

  describe "#current_version" do
    let(:instance) { model_class.new }

    it "responds to current_version method" do
      expect(instance).to respond_to(:current_version)
    end

    it "returns 0 when no revisions exist" do
      expect(instance.current_version).to eq(0)
    end
  end

  describe "#create_snapshot!" do
    let(:instance) { model_class.new }

    it "responds to create_snapshot! method" do
      expect(instance).to respond_to(:create_snapshot!)
    end
  end

  describe "#revision_sql" do
    let(:post) { Post.create!(title: "Test", body: "Body") }

    it "responds to revision_sql method" do
      expect(post).to respond_to(:revision_sql)
    end

    it "generates insert SQL for next revision" do
      sql = post.revision_sql
      expect(sql).to include("INSERT")
      expect(sql).to include("post_revisions")
      expect(sql).to include("post_id")
      expect(sql).to include("version")
    end

    it "generates upsert SQL when requested" do
      sql = post.revision_sql(upsert: true)
      expect(sql).to include("ON CONFLICT")
      expect(sql).to include("DO UPDATE SET")
    end

    it "returns empty SQL for non-persisted record" do
      new_post = Post.new(title: "New")
      expect(new_post.revision_sql).to eq("")
    end
  end

  describe "#revert_to" do
    let(:instance) { model_class.new }

    it "responds to revert_to method" do
      expect(instance).to respond_to(:revert_to)
    end
  end

  describe "#versions" do
    let(:instance) { model_class.new }

    it "responds to versions method" do
      expect(instance).to respond_to(:versions)
    end

    it "returns an enumerator" do
      expect(instance.versions).to be_a(Enumerator)
    end
  end

  describe "#at_version" do
    let(:instance) { model_class.new }

    it "responds to at_version method" do
      expect(instance).to respond_to(:at_version)
    end
  end

  describe "#refresh_attributes" do
    let(:post) { Post.create!(title: "Test", body: "Body") }

    it "refreshes columns with default functions" do
      # refresh_attributes is called internally by create_snapshot!
      # Test it indirectly through create_snapshot!
      post.title = "Updated"
      snapshot = post.create_snapshot!
      expect(snapshot).to be_present
    end
  end

  describe "#create_snapshot!" do
    let(:post) { Post.create!(title: "Test", body: "Body") }

    it "creates a snapshot with use_old_values option" do
      post.title = "Updated"
      snapshot = post.create_snapshot!(use_old_values: true)
      expect(snapshot).to be_present
      expect(snapshot.version).to eq(1)
    end

    it "handles RecordInvalid error with detailed message" do
      allow(post.revisions).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(post.revisions.build))
      expect { post.create_snapshot! }.to raise_error(/Failed to create revision/)
    end

    it "handles generic errors with detailed message" do
      allow(post.revisions).to receive(:create!).and_raise(StandardError.new("Database error"))
      expect { post.create_snapshot! }.to raise_error(/Failed to create revision/)
    end

    it "redacts revision values from error message" do
      post.title = "top-secret-title"
      post.body = "token-abc-123"
      allow(post.revisions).to receive(:create!).and_raise(StandardError.new("Database error"))

      expect {
        post.create_snapshot!
      }.to raise_error do |error|
        message = error.message
        expect(message).to include("Failed to create revision: StandardError")
        expect(message).to include("Revision attribute keys:")
        expect(message).to include("Identity keys:")
        expect(message).to include("Version column:")
        expect(message).not_to include("token-abc-123")
        expect(message).not_to include("top-secret-title")
      end
    end

    it "creates snapshot with only option" do
      snapshot = post.create_snapshot!(only: [:title])
      expect(snapshot).to be_present
      expect(snapshot.title).to eq("Test")
    end

    it "creates snapshot with except option" do
      snapshot = post.create_snapshot!(except: [:body])
      expect(snapshot).to be_present
      expect(snapshot.title).to eq("Test")
    end
  end

  describe "#undo!" do
    let(:post) { Post.create!(title: "v1") }

    it "returns false when no previous revision exists" do
      expect(post.undo!).to be false
    end

    it "switches to previous version" do
      post.update!(title: "v2")
      post.update!(title: "v3")
      # 2 revisions (v1, v2); undo goes to second-to-last = rev 1 (v1)
      result = post.undo!
      expect(result).to be true
      expect(post.title).to eq("v1")
    end

    it "supports append option" do
      post.update!(title: "v2")
      post.update!(title: "v3")
      post.undo!(append: true) # Appends rev with v1 data; now 3 revisions total
      expect(post.revisions.count).to eq(3)
    end
  end

  describe "#redo!" do
    let(:post) { Post.create!(title: "v1") }

    it "returns false when no next revision exists" do
      expect(post.redo!).to be false
    end

    it "switches to next version when a next revision exists" do
      post.update!(title: "v2")
      post.update!(title: "v3")
      post.undo! # Now at v1 (only 2 revisions: v1, v2; undo goes to rev 1)
      result = post.redo! # Next revision is v2
      expect(result).to be true
      expect(post.title).to eq("v2")
    end
  end

  describe "#switch_to!" do
    let(:post) { Post.create!(title: "v1") }

    it "returns false when version does not exist" do
      expect(post.switch_to!(999)).to be false
    end

    it "switches to specified version" do
      post.update!(title: "v2")
      post.update!(title: "v3")
      result = post.switch_to!(1)
      expect(result).to be true
      expect(post.title).to eq("v1")
    end

    it "supports append option for older versions" do
      post.update!(title: "v2")
      post.update!(title: "v3")
      result = post.switch_to!(1, append: true)
      expect(result).to be true
      expect(post.revisions.count).to eq(3) # Creates new revision with v1 data
    end
  end

  describe "#apply_revision_diff" do
    let(:post) { Post.create!(title: "Original", body: "Body") }

    it "applies changes to record" do
      changes = {"title" => "Updated"}
      post.apply_revision_diff(1, changes)
      expect(post.title).to eq("Updated")
    end

    it "skips deleted columns" do
      changes = {"deleted_column" => "value"}
      allow(post).to receive(:deleted_column?).with("deleted_column").and_return(true)
      post.apply_revision_diff(1, changes)
      expect(post).not_to respond_to(:deleted_column)
    end

    it "skips columns that don't exist" do
      changes = {"nonexistent" => "value"}
      post.apply_revision_diff(1, changes)
      expect(post).not_to respond_to(:nonexistent)
    end
  end

  describe "#deserialize_value" do
    let(:post) { Post.create!(title: "Test") }

    it "deserializes value using attribute type" do
      value = post.deserialize_value("title", "Deserialized")
      expect(value).to eq("Deserialized")
    end

    it "falls back to raw value on error" do
      # Test normal case
      value = post.deserialize_value("title", "Raw")
      expect(value).to eq("Raw")

      # Test error path - mock the @attributes access to cause an error
      allow(post).to receive(:has_attribute?).and_return(true)
      allow(post).to receive(:instance_variable_get).with(:@attributes).and_raise(StandardError.new("error"))

      value = post.deserialize_value("title", "Raw")
      expect(value).to eq("Raw")
    end
  end

  describe "#should_merge_with_previous?" do
    let(:post) { Post.create!(title: "v1") }

    it "returns false when no revisions exist" do
      new_post = Post.new(title: "New")
      expect(new_post.should_merge_with_previous?(1.0, Time.current)).to be false
    end

    it "returns true when within debounce time" do
      post.update!(title: "v2")
      timestamp = post.revisions.last.created_at + 0.5.seconds
      expect(post.should_merge_with_previous?(1.0, timestamp)).to be true
    end

    it "returns false when outside debounce time" do
      post.update!(title: "v2")
      timestamp = post.revisions.last.created_at + 2.seconds
      expect(post.should_merge_with_previous?(1.0, timestamp)).to be false
    end
  end

  describe "#merge_with_previous_revision!" do
    let(:post) { Post.create!(title: "v1") }

    it "merges with previous revision within debounce time" do
      post.update!(title: "v2")
      post.title = "v3"
      post.merge_with_previous_revision!(Time.current, nil, nil, false)
      expect(post.revisions.count).to eq(1) # Still only one revision
    end

    it "respects only option when merging" do
      post.update!(title: "v2", body: "body2")
      post.title = "v3"
      post.merge_with_previous_revision!(Time.current, [:title], nil, false)
      revision = post.revisions.last
      expect(revision.title).to eq("v3")
    end

    it "respects except option when merging" do
      post.update!(title: "v1", body: "body1")
      post.update!(title: "v2", body: "body2") # last revision has old state: v1, body1
      post.body = "body3" # Only body changed (unsaved); title stays "v2"
      post.merge_with_previous_revision!(Time.current, nil, [:body], false)
      revision = post.revisions.reload.last
      # except: [:body] excludes body from snapshot; body preserved from last revision (body1)
      expect(revision.title).to eq("v2")
      expect(revision.body).to eq("body1")
    end

    it "uses old values when use_old_values is true" do
      post.update!(title: "v2")
      post.title = "v3"
      post.merge_with_previous_revision!(Time.current, nil, nil, true)
      revision = post.revisions.last
      expect(revision.title).to eq("v2") # Should use old value
    end
  end

  describe "#snapshot_base_attributes" do
    let(:post) { Post.create!(title: "Test", body: "Body") }

    it "returns current attributes when use_old_values is false" do
      post.title = "Updated"
      attrs = post.snapshot_base_attributes(false)
      expect(attrs["title"]).to eq("Updated")
    end

    it "returns database attributes when use_old_values is true" do
      post.title = "Updated"
      attrs = post.snapshot_base_attributes(true)
      expect(attrs["title"]).to eq("Test") # Should be persisted value
    end

    it "falls back to attributes when attributes_in_database is not available" do
      post.title = "Updated"
      # Mock respond_to? to return false for attributes_in_database
      original_respond_to = post.method(:respond_to?)
      allow(post).to receive(:respond_to?) do |method, *args|
        if method == :attributes_in_database
          false
        else
          original_respond_to.call(method, *args)
        end
      end
      attrs = post.snapshot_base_attributes(true)
      expect(attrs).to be_a(Hash)
      expect(attrs["title"]).to be_present
    end
  end
end
