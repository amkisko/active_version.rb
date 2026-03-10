require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Context System", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
    ActiveVersion::RequestStore.audited_user = nil
    ActiveVersion::RequestStore.request_uuid = nil
    ActiveVersion::RequestStore.remote_address = nil
    ActiveVersion.context = {}
    ActiveVersion.clear_context!
    ActiveVersion.config.execution_scope = :fiber
  end

  describe "ActiveVersion.context" do
    it "returns empty hash by default" do
      expect(ActiveVersion.context).to eq({})
    end

    it "allows setting context" do
      ActiveVersion.context = {ip: "127.0.0.1"}
      expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")
    end

    it "merges persistent and request-scoped context" do
      ActiveVersion.with_context!({ip: "192.168.1.1"})
      ActiveVersion.context = {user_agent: "Mozilla"}

      expect(ActiveVersion.context[:ip]).to eq("192.168.1.1")
      expect(ActiveVersion.context[:user_agent]).to eq("Mozilla")
    end
  end

  describe "ActiveVersion.with_context" do
    it "sets context within block" do
      ActiveVersion.with_context({ip: "127.0.0.1"}) do
        expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")
      end
    end

    it "restores context after block" do
      ActiveVersion.context = {ip: "original"}
      ActiveVersion.with_context({ip: "127.0.0.1"}) do
        expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")
      end
      expect(ActiveVersion.context[:ip]).to eq("original")
    end

    it "merges context with existing" do
      ActiveVersion.context = {ip: "original"}
      ActiveVersion.with_context({user_agent: "Mozilla"}) do
        expect(ActiveVersion.context[:ip]).to eq("original")
        expect(ActiveVersion.context[:user_agent]).to eq("Mozilla")
      end
    end

    it "supports transactional context for PostgreSQL" do
      skip "PostgreSQL required" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"

      ActiveVersion.with_context({ip: "127.0.0.1"}, transactional: true) do
        post = Post.create!(title: "Test")
        post.title = "Updated"
        post.save!

        audit = post.audits.last
        expect(audit.audited_context[:ip]).to eq("127.0.0.1")
      end
    end

    it "supports non-transactional context" do
      ActiveVersion.with_context({ip: "127.0.0.1"}, transactional: false) do
        expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")
      end
    end

    it "does not raise with transactional mode outside explicit transactions on PostgreSQL" do
      skip "PostgreSQL required" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
      expect(ActiveRecord::Base.connection.open_transactions).to eq(0)

      expect do
        ActiveVersion.with_context({ip: "127.0.0.1"}, transactional: true) do
          Post.create!(title: "Test")
        end
      end.not_to raise_error
    end

    it "falls back to thread-local context when no database connection is available" do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect do
        ActiveVersion.with_context({ip: "127.0.0.1"}, transactional: true) do
          expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")
        end
      end.not_to raise_error
    end
  end

  describe "ActiveVersion.with_context!" do
    it "sets persistent context" do
      ActiveVersion.with_context!({ip: "127.0.0.1"})
      expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")
    end

    it "persists across operations" do
      ActiveVersion.with_context!({ip: "127.0.0.1"})

      post1 = Post.create!(title: "Test 1")
      post1.title = "Updated 1"
      post1.save!

      post2 = Post.create!(title: "Test 2")
      post2.title = "Updated 2"
      post2.save!

      expect(post1.audits.last.audited_context[:ip]).to eq("127.0.0.1")
      expect(post2.audits.last.audited_context[:ip]).to eq("127.0.0.1")
    end

    it "raises error when called from within with_context block" do
      ActiveVersion.with_context({ip: "127.0.0.1"}) do
        expect {
          ActiveVersion.with_context!({ip: "192.168.1.1"})
        }.to raise_error(ActiveVersion::Error, /cannot be called from within/)
      end
    end

    it "keeps with_context! blocked for nested with_context blocks" do
      ActiveVersion.with_context({ip: "outer"}) do
        ActiveVersion.with_context({user_agent: "inner"}) do
          expect(ActiveVersion.context[:ip]).to eq("outer")
          expect(ActiveVersion.context[:user_agent]).to eq("inner")
        end

        expect {
          ActiveVersion.with_context!({ip: "should_fail"})
        }.to raise_error(ActiveVersion::Error, /cannot be called from within/)
      end
    end
  end

  describe "ActiveVersion.clear_context!" do
    it "clears persistent context" do
      ActiveVersion.with_context!({ip: "127.0.0.1"})
      expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")

      ActiveVersion.clear_context!
      expect(ActiveVersion.context[:ip]).to be_nil
    end

    it "does not affect request-scoped context" do
      ActiveVersion.context = {user_agent: "Mozilla"}
      ActiveVersion.with_context!({ip: "127.0.0.1"})

      ActiveVersion.clear_context!
      expect(ActiveVersion.context[:user_agent]).to eq("Mozilla")
      expect(ActiveVersion.context[:ip]).to be_nil
    end
  end

  describe "context in audits" do
    it "includes context in audit records" do
      ActiveVersion.context = {ip: "127.0.0.1", user_agent: "Mozilla"}

      post = Post.create!(title: "Test")
      audit = post.audits.last

      expect(audit.audited_context[:ip]).to eq("127.0.0.1")
      expect(audit.audited_context[:user_agent]).to eq("Mozilla")
    end

    it "merges instance context with global context" do
      ActiveVersion.context = {ip: "127.0.0.1"}

      post = Post.create!(title: "Test", status: "draft")
      post.audit_context = {user_agent: "Mozilla"}
      post.update!(status: "published")

      audit = post.audits.last
      expect(audit.audited_context[:ip]).to eq("127.0.0.1")
      expect(audit.audited_context[:user_agent]).to eq("Mozilla")
    end

    it "instance context takes precedence over global" do
      ActiveVersion.context = {ip: "127.0.0.1"}

      post = Post.create!(title: "Test", status: "draft")
      post.audit_context = {ip: "192.168.1.1"}
      post.update!(status: "published")

      audit = post.audits.last
      expect(audit.audited_context[:ip]).to eq("192.168.1.1")
    end

    it "preserves persistent context when using with_context blocks" do
      ActiveVersion.with_context!({request_id: "persistent-1"})
      post = Post.create!(title: "Test", status: "draft")

      ActiveVersion.with_context({ip: "127.0.0.1"}) do
        post.update!(status: "published")
      end

      audit = post.audits.last
      expect(audit.audited_context[:request_id]).to eq("persistent-1")
      expect(audit.audited_context[:ip]).to eq("127.0.0.1")
    end
  end

  describe "fiber/thread execution scope" do
    after do
      ActiveVersion.config.execution_scope = :fiber
      ActiveVersion.clear_context!
    end

    it "keeps persistent context fiber-local by default" do
      ActiveVersion.config.execution_scope = :fiber
      ActiveVersion.with_context!({request_id: "main"})

      value_from_fiber = nil
      Fiber.new do
        value_from_fiber = ActiveVersion.context[:request_id]
      end.resume

      expect(ActiveVersion.context[:request_id]).to eq("main")
      expect(value_from_fiber).to be_nil
    end

    it "shares persistent context across fibers when execution_scope is :thread" do
      ActiveVersion.config.execution_scope = :thread
      ActiveVersion.with_context!({request_id: "main"})

      value_from_fiber = nil
      Fiber.new do
        value_from_fiber = ActiveVersion.context[:request_id]
      end.resume

      expect(value_from_fiber).to eq("main")
    end
  end
end
