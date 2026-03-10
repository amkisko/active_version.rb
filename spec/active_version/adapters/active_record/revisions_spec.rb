require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe ActiveVersion::Adapters::ActiveRecord::Revisions do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  describe "has_revisions" do
    it "includes HasRevisions module" do
      test_class = Class.new(ActiveRecord::Base) do
        self.table_name = "posts"
        has_revisions
      end

      expect(test_class.included_modules).to include(ActiveVersion::Revisions::HasRevisions)
    end

    it "extends SQLBuilder::ClassMethods" do
      test_class = Class.new(ActiveRecord::Base) do
        self.table_name = "posts"
        has_revisions
      end

      expect(test_class.singleton_class.included_modules).to include(ActiveVersion::Revisions::SQLBuilder::ClassMethods)
    end

    it "registers the model with ActiveVersion.registry" do
      test_class = Class.new(ActiveRecord::Base) do
        self.table_name = "posts"
        has_revisions
      end

      config = ActiveVersion.registry.config_for(test_class, :revisions)
      expect(config).to be_a(Hash)
    end

    it "registers revision class when it exists" do
      test_class = Class.new(ActiveRecord::Base) do
        self.table_name = "posts"
      end

      # Create a revision class
      revision_class_name = "#{test_class.name}Revision"
      revision_class = Class.new(ActiveRecord::Base)
      test_class.const_set(revision_class_name, revision_class)

      test_class.has_revisions

      registered_class = ActiveVersion.registry.version_class_for(test_class, :revisions)
      expect(registered_class).to eq(revision_class)
    end

    it "does not raise error when revision class does not exist" do
      test_class = Class.new(ActiveRecord::Base) do
        self.table_name = "posts"
      end

      expect { test_class.has_revisions }.not_to raise_error
    end

    it "installs revision callbacks and creates revisions via adapter DSL" do
      Post.destroy_all
      PostRevision.destroy_all

      test_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "AdapterDslRevisionPost"
        end

        has_revisions as: PostRevision
      end

      callbacks = test_class._update_callbacks.select { |cb| cb.filter == :create_revision_before_update }
      expect(callbacks).not_to be_empty
      expect(test_class.revision_options[:on]).to eq([:update])

      post = test_class.create!(title: "v1")
      post.update!(title: "v2")

      expect(post.revisions.count).to eq(1)
      expect(post.revisions.first.title).to eq("v1")
    end

    it "respects on: [] when configured through adapter DSL" do
      Post.destroy_all
      PostRevision.destroy_all

      test_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "AdapterDslManualRevisionPost"
        end

        has_revisions as: PostRevision, on: []
      end

      callbacks = test_class._update_callbacks.select { |cb| cb.filter == :create_revision_before_update }
      expect(callbacks).to be_empty
    end
  end

  describe "ActiveSupport.on_load hook" do
    it "includes the module when ActiveRecord loads" do
      # The module should be included via ActiveSupport.on_load
      # This is tested implicitly through the has_revisions method being available
      expect(ActiveRecord::Base).to respond_to(:has_revisions)
    end
  end

  describe "immediate inclusion for already loaded ActiveRecord::Base" do
    it "includes the module if ActiveRecord::Base is already loaded" do
      # This tests the fallback inclusion at the bottom of the file
      # Since ActiveRecord::Base is loaded in tests, this should work
      expect(ActiveRecord::Base.included_modules).to include(ActiveVersion::Adapters::ActiveRecord::Revisions)
    end
  end
end
