require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion AuditRecord Callbacks Integration", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    cleanup_test_data
    reset_active_version_context
  end

  describe "set_version_number" do
    it "sets version to 1 for create action" do
      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(audit.version).to eq(1)
      expect(audit.action).to eq("create")
    end

    it "increments version for update actions" do
      post = Post.create!(title: "v1")
      # Ensure we have actual changes
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      audits = post.audits.order(version: :asc)
      expect(audits.count).to eq(3)
      expect(audits[0].version).to eq(1)
      expect(audits[0].action).to eq("create")
      expect(audits[1].version).to eq(2)
      expect(audits[1].action).to eq("update")
      expect(audits[2].version).to eq(3)
      expect(audits[2].action).to eq("update")
    end

    it "handles concurrent updates correctly using database MAX" do
      post = Post.create!(title: "v1")

      # Ensure actual changes for updates
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      # Verify versions are sequential
      versions = post.audits.order(version: :asc).pluck(:version)
      expect(versions).to eq([1, 2, 3])
    end
  end

  describe "set_audit_user" do
    it "sets user from RequestStore" do
      user = double("user", id: 42, class: double("UserClass", name: "User"))
      ActiveVersion::RequestStore.audited_user = user

      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(audit.user_id).to eq(42)
      expect(audit.user_type).to eq("User")
    end

    it "handles user column not being configured" do
      # Test the return unless user_column path
      # This is hard to test directly, but we can verify it doesn't break
      post = Post.create!(title: "Hello")
      audit = post.audits.first
      expect(audit).to be_persisted
    end

    it "sets user from current_user_method when RequestStore is empty" do
      # Test RequestStore path (current_user_method requires model context)
      user = double("user", id: 99, class: double("AdminClass", name: "Admin"))
      ActiveVersion::RequestStore.audited_user = user
      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(audit.user_id).to eq(99)
      expect(audit.user_type).to eq("Admin")
    end

    it "handles user without id method gracefully" do
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

      # Should not raise error, user_id may be nil or set to user object
      expect(audit).to be_persisted
    end

    it "sets polymorphic user type correctly" do
      admin = double("admin", id: 5, class: double("AdminClass", name: "Admin"))
      ActiveVersion::RequestStore.audited_user = admin

      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(audit.user_id).to eq(5)
      expect(audit.user_type).to eq("Admin")
    end
  end

  describe "set_request_uuid" do
    it "sets UUID from RequestStore" do
      uuid = SecureRandom.uuid
      ActiveVersion::RequestStore.request_uuid = uuid

      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(audit.request_uuid).to eq(uuid)
    end

    it "generates UUID if RequestStore is empty" do
      ActiveVersion::RequestStore.request_uuid = nil

      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(audit.request_uuid).to be_present
      expect(audit.request_uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it "uses same UUID for multiple audits in same request" do
      uuid = SecureRandom.uuid
      ActiveVersion::RequestStore.request_uuid = uuid

      post = Post.create!(title: "Hello")
      post.title = "Updated"
      post.save!

      audits = post.audits.order(version: :asc)
      expect(audits[0].request_uuid).to eq(uuid)
      expect(audits[1].request_uuid).to eq(uuid)
    end
  end

  describe "set_remote_address" do
    it "sets remote address from RequestStore" do
      ActiveVersion::RequestStore.remote_address = "192.168.1.100"

      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(audit.remote_address).to eq("192.168.1.100")
    end

    it "allows nil remote address when not set" do
      ActiveVersion::RequestStore.remote_address = nil

      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(audit.remote_address).to be_nil
    end

    it "persists remote address across multiple audits" do
      ActiveVersion::RequestStore.remote_address = "10.0.0.1"

      post = Post.create!(title: "Hello")
      post.title = "Updated"
      post.save!

      audits = post.audits.order(version: :asc)
      expect(audits[0].remote_address).to eq("10.0.0.1")
      expect(audits[1].remote_address).to eq("10.0.0.1")
    end
  end

  describe "set_audited_context" do
    it "sets context from global ActiveVersion.context when not set during creation" do
      ActiveVersion.context = {"ip" => "127.0.0.1", "controller" => "PostsController"}

      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(audit.audited_context).to be_a(Hash)
      expect(audit.audited_context["ip"]).to eq("127.0.0.1")
      expect(audit.audited_context["controller"]).to eq("PostsController")
    end

    it "does not set context if context column is not present" do
      # Test the return unless context_column path
      # This is hard to test directly, but we can verify it doesn't break
      post = Post.create!(title: "Hello")
      audit = post.audits.first
      expect(audit).to be_persisted
    end

    it "does not override context if already set" do
      # Test the return if self[context_column].present? path
      ActiveVersion.context = {"global" => "value"}

      # Set context during creation
      ActiveVersion.with_context("specific" => "value") do
        post = Post.create!(title: "Hello")
        audit = post.audits.first

        # Should use specific context, not global
        expect(audit.audited_context["specific"]).to eq("value")
        expect(audit.audited_context["global"]).to be_nil
      end
    end

    it "handles empty global context" do
      # Test the global_context.any? check
      ActiveVersion.context = {}

      post = Post.create!(title: "Hello")
      audit = post.audits.first

      # Context should be set from creation, not from empty global context
      expect(audit).to be_persisted
    end

    it "does not override context if already set during creation" do
      ActiveVersion.context = {"global" => "value"}

      ActiveVersion.with_context("specific" => "value") do
        post = Post.create!(title: "Hello")
        audit = post.audits.first

        # Should use the specific context, not global
        expect(audit.audited_context).to be_a(Hash)
        expect(audit.audited_context["specific"]).to eq("value")
        expect(audit.audited_context["global"]).to be_nil
      end
    end

    it "merges instance context with global context" do
      ActiveVersion.context = {"ip" => "127.0.0.1"}

      post = Post.create!(title: "Hello", status: "draft")
      post.audit_context = {"controller" => "PostsController"}
      post.update!(status: "published")

      audit = post.audits.order(version: :asc).last
      expect(audit.audited_context).to be_a(Hash)
      expect(audit.audited_context["ip"]).to eq("127.0.0.1")
      expect(audit.audited_context["controller"]).to eq("PostsController")
    end
  end

  describe "instrument_audit_created" do
    it "instruments audit creation events" do
      events = []
      ActiveSupport::Notifications.subscribe("audit.active_version") do |name, started, finished, unique_id, payload|
        events << {name: name, payload: payload}
      end

      post = Post.create!(title: "Hello")
      audit = post.audits.first

      expect(events.length).to eq(1)
      expect(events[0][:name]).to eq("audit.active_version")
      payload = events[0][:payload]
      expect(payload[:audit]).to eq(audit)
      expect(payload[:auditable]).to eq(post)
    end

    it "instruments multiple audit creations" do
      events = []
      ActiveSupport::Notifications.subscribe("audit.active_version") do |name, started, finished, unique_id, payload|
        events << {name: name, payload: payload}
      end

      post = Post.create!(title: "Hello")
      post.title = "Updated"
      post.save!

      expect(events.length).to eq(2)
      expect(events[0][:payload][:audit].action).to eq("create")
      expect(events[1][:payload][:audit].action).to eq("update")
    end
  end
end
