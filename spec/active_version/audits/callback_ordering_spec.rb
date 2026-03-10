require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Callback Ordering", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
  end

  describe "on: [] option" do
    let(:custom_post_class) do
      Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "CustomPost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits on: [], as: PostAudit
      end
    end

    it "does not install callbacks automatically" do
      instance = custom_post_class.new(title: "Test")
      expect(instance).not_to receive(:audit_create)
      instance.save!
    end

    it "allows manual callback installation" do
      custom_post_class.audit_on_create
      instance = custom_post_class.new(title: "Test")
      instance.save!

      expect(instance.audits.count).to eq(1)
    end
  end

  describe "manual callback methods" do
    let(:custom_post_class) do
      Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "ManualPost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits on: [], as: PostAudit

        # Install callbacks in specific order
        audit_on_create
        audit_on_update
        audit_on_destroy
      end
    end

    it "audit_on_create installs after_create callback" do
      instance = custom_post_class.new(title: "Test")
      instance.save!
      expect(instance.audits.count).to eq(1)
      expect(instance.audits.last.action).to eq("create")
    end

    it "audit_on_update installs before_update callback" do
      instance = custom_post_class.create!(title: "Test")
      instance.title = "Updated"
      instance.save!
      expect(instance.audits.count).to eq(2)
      expect(instance.audits.last.action).to eq("update")
    end

    it "audit_on_destroy installs before_destroy callback" do
      instance = custom_post_class.create!(title: "Test")
      instance.destroy
      expect(instance.audits.count).to eq(2) # create + destroy
      expect(instance.audits.last.action).to eq("destroy")
    end

    it "allows custom callback order" do
      ordered_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "OrderedPost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits on: [], as: PostAudit

        # Custom order: destroy first, then update, then create
        audit_on_destroy
        audit_on_update
        audit_on_create
      end

      instance = ordered_class.create!(title: "Test")
      expect(instance.audits.count).to eq(1)
    end
  end
end
