require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Error Handling", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
    ActiveVersion.config.audit_error_behavior = :log
    ActiveVersion.config.revision_error_behavior = :exception
  end

  describe "configurable error behavior" do
    it "logs errors by default" do
      allow(PostAudit).to receive(:create!).and_raise(StandardError.new("Database error"))
      logger = double("logger")
      allow(logger).to receive(:warn)
      allow(ActiveVersion).to receive(:logger).and_return(logger)

      post = Post.create!(title: "Test")
      post.title = "Updated"
      post.save!

      expect(logger).to have_received(:warn).at_least(:once).with(/Unable to create audit/)
    end

    it "raises exception when error_behavior is :exception" do
      ActiveVersion.config.audit_error_behavior = :exception
      post = Post.create!(title: "Test")
      allow(PostAudit).to receive(:create!).and_raise(StandardError.new("Database error"))
      expect {
        post.title = "Updated"
        post.save!
      }.to raise_error(StandardError, "Database error")
    end

    it "raises exception for create action when error_behavior is :exception" do
      ActiveVersion.config.audit_error_behavior = :exception
      allow(PostAudit).to receive(:create!).and_raise(StandardError.new("Create audit failed"))

      expect {
        Post.create!(title: "Test")
      }.to raise_error(StandardError, "Create audit failed")
    end

    it "silently ignores errors when error_behavior is :silent" do
      ActiveVersion.config.audit_error_behavior = :silent
      allow(PostAudit).to receive(:create!).and_raise(StandardError.new("Database error"))
      logger = double("logger")
      allow(logger).to receive(:warn)
      allow(ActiveVersion).to receive(:logger).and_return(logger)

      post = Post.create!(title: "Test")
      post.title = "Updated"
      post.save!

      expect(logger).not_to have_received(:warn)
    end

    it "allows per-model error behavior" do
      custom_post_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "CustomPost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits error_behavior: :exception
      end

      post = custom_post_class.create!(title: "Test")
      allow(PostAudit).to receive(:create!).and_raise(StandardError.new("Database error"))
      expect {
        post.title = "Updated"
        post.save!
      }.to raise_error(StandardError)
    end
  end

  describe "revision error behavior" do
    let(:post) { Post.create!(title: "Test", body: "Body") }

    it "raises when revision_error_behavior is :exception" do
      ActiveVersion.config.revision_error_behavior = :exception
      allow(post.revisions).to receive(:create!).and_raise(StandardError.new("Database error"))

      expect { post.create_snapshot! }.to raise_error(/Failed to create revision/)
    end

    it "logs when revision_error_behavior is :log" do
      ActiveVersion.config.revision_error_behavior = :log
      allow(post.revisions).to receive(:create!).and_raise(StandardError.new("Database error"))
      logger = double("logger")
      allow(logger).to receive(:warn)
      allow(ActiveVersion).to receive(:logger).and_return(logger)

      expect(post.create_snapshot!).to be_nil
      expect(logger).to have_received(:warn).with(/Failed to create revision/)
    end

    it "silently ignores revision errors when revision_error_behavior is :silent" do
      ActiveVersion.config.revision_error_behavior = :silent
      allow(post.revisions).to receive(:create!).and_raise(StandardError.new("Database error"))
      logger = double("logger")
      allow(logger).to receive(:warn)
      allow(ActiveVersion).to receive(:logger).and_return(logger)

      expect(post.create_snapshot!).to be_nil
      expect(logger).not_to have_received(:warn)
    end
  end
end
