require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion Additional Context Integration", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    # Clear RequestStore first to avoid using leaked doubles in destroy callbacks
    ActiveVersion::RequestStore.audited_user = nil
    ActiveVersion::RequestStore.request_uuid = nil
    ActiveVersion::RequestStore.remote_address = nil
    ActiveVersion.context = {}
    cleanup_test_data
  end

  describe "audited_context" do
    it "captures context from ActiveVersion.context" do
      ActiveVersion.with_context(ip: "127.0.0.1", user_agent: "Test") do
        post = Post.create!(title: "Hello")

        audit = post.audits.first
        expect(audit.audited_context).to include("ip" => "127.0.0.1")
        expect(audit.audited_context).to include("user_agent" => "Test")
      end
    end

    it "merges instance context with global context" do
      # Set global context
      ActiveVersion.with_context(ip: "127.0.0.1", request_id: "abc123") do
        # Create initial record with global context
        post = Post.create!(title: "Hello")
        create_audit = post.audits.first
        expect(create_audit.audited_context).to include("ip" => "127.0.0.1")
        expect(create_audit.audited_context).to include("request_id" => "abc123")

        # Set instance context before update
        post.audit_context = {controller: "PostsController", action: "update"}

        # Perform update with actual changes
        post.update!(status: "published")

        # Verify update audit captured both contexts
        post.reload
        update_audit = post.audits.order(version: :asc).last
        expect(update_audit).to be_present
        expect(update_audit.action).to eq("update")

        # Verify context merging - global context should be present
        expect(update_audit.audited_context).to be_a(Hash)
        expect(update_audit.audited_context["ip"]).to eq("127.0.0.1")
        expect(update_audit.audited_context["request_id"]).to eq("abc123")

        # Instance context should override/merge with global
        expect(update_audit.audited_context["controller"]).to eq("PostsController")
        expect(update_audit.audited_context["action"]).to eq("update")
      end
    end

    it "allows setting context per instance" do
      # Create record without global context
      post = Post.create!(title: "Hello")

      # Set instance context before update
      post.audit_context = {custom: "value", source: "test"}

      # Perform update with actual changes
      post.update!(status: "published")

      # Verify update audit captured instance context
      post.reload
      update_audit = post.audits.order(version: :asc).last
      expect(update_audit).to be_present
      expect(update_audit.action).to eq("update")

      # Verify context was captured
      expect(update_audit.audited_context).to be_a(Hash)
      expect(update_audit.audited_context["custom"]).to eq("value")
      expect(update_audit.audited_context["source"]).to eq("test")
    end
  end

  describe "request_uuid" do
    it "captures request UUID from RequestStore" do
      uuid = SecureRandom.uuid
      ActiveVersion::RequestStore.request_uuid = uuid

      post = Post.create!(title: "Hello")

      audit = post.audits.first
      expect(audit.request_uuid).to eq(uuid)
    end

    it "generates UUID if not provided" do
      post = Post.create!(title: "Hello")

      audit = post.audits.first
      expect(audit.request_uuid).to be_present
      expect(audit.request_uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end
  end

  describe "remote_address" do
    it "captures remote address from RequestStore" do
      ActiveVersion::RequestStore.remote_address = "192.168.1.1"

      post = Post.create!(title: "Hello")

      audit = post.audits.first
      expect(audit.remote_address).to eq("192.168.1.1")
    end

    it "allows nil remote address" do
      post = Post.create!(title: "Hello")

      audit = post.audits.first
      # remote_address may be nil if not set
      expect(audit.remote_address).to be_nil.or(be_a(String))
    end
  end

  describe "audited_user" do
    it "captures user from RequestStore" do
      user = double("user", id: 1, class: double("UserClass", name: "User"))
      ActiveVersion::RequestStore.audited_user = user

      post = Post.create!(title: "Hello")

      audit = post.audits.first
      expect(audit.user_id).to eq(1)
      expect(audit.user_type).to eq("User")
    end

    it "handles polymorphic user" do
      admin = double("admin", id: 2, class: double("AdminClass", name: "Admin"))
      ActiveVersion::RequestStore.audited_user = admin

      post = Post.create!(title: "Hello")

      audit = post.audits.first
      expect(audit.user_id).to eq(2)
      expect(audit.user_type).to eq("Admin")
    end

    it "handles user without id method" do
      user_class = double("UserClass", name: "User")
      user = Class.new do
        def initialize(klass)
          @klass = klass
        end

        def class
          @klass
        end

        def respond_to?(method_name, include_all = false)
          return false if method_name == :id
          super
        end
      end.new(user_class)
      ActiveVersion::RequestStore.audited_user = user

      post = Post.create!(title: "Hello")

      audit = post.audits.first
      # Should handle gracefully
      expect(audit).to be_present
    end
  end

  describe "combined context" do
    it "captures all context fields together" do
      user = double("user", id: 1, class: double("UserClass", name: "User"))
      uuid = SecureRandom.uuid

      ActiveVersion::RequestStore.audited_user = user
      ActiveVersion::RequestStore.request_uuid = uuid
      ActiveVersion::RequestStore.remote_address = "10.0.0.1"

      ActiveVersion.with_context(controller: "PostsController", action: "create") do
        post = Post.create!(title: "Hello")

        audit = post.audits.first
        expect(audit.user_id).to eq(1)
        expect(audit.request_uuid).to eq(uuid)
        expect(audit.remote_address).to eq("10.0.0.1")
        expect(audit.audited_context).to include("controller" => "PostsController")
        expect(audit.audited_context).to include("action" => "create")
      end
    end
  end
end
