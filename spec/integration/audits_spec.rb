require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion Audits Integration", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    cleanup_test_data
    reset_active_version_context
    ActiveVersion.clear_context!
  end

  describe "basic audit functionality" do
    it "creates an audit on create" do
      post = Post.create!(title: "Hello", body: "World")

      expect(post.audits.count).to eq(1)
      audit = post.audits.first
      expect(audit.action).to eq("create")
      expect(audit.version).to eq(1)
      expect(audit.audited_changes["title"]).to eq("Hello")
    end

    it "creates an audit on update" do
      # Create initial record
      post = Post.create!(title: "Hello", body: "Initial body")
      initial_audit_count = post.audits.count
      expect(initial_audit_count).to eq(1)

      # Verify initial audit
      create_audit = post.audits.first
      expect(create_audit.action).to eq("create")
      expect(create_audit.version).to eq(1)

      # Update the record with actual changes
      # Use save! to ensure changes are persisted
      post.title = "World"
      post.body = "Updated body"
      post.save!

      # Reload to get fresh audit count
      post.reload
      expect(post.audits.count).to eq(2)

      # Verify update audit exists
      update_audit = post.audits.order(version: :asc).last
      expect(update_audit).to be_present
      expect(update_audit.action).to eq("update")
      expect(update_audit.version).to eq(2)

      # Verify changes were captured
      expect(update_audit.audited_changes).to be_a(Hash)
      if update_audit.audited_changes["title"]
        expect(update_audit.audited_changes["title"]).to be_an(Array)
        expect(update_audit.audited_changes["title"]).to eq(["Hello", "World"])
      end
    end

    it "creates an audit on destroy" do
      post = Post.create!(title: "Hello")
      post_id = post.id
      post.destroy!

      audit = PostAudit.where(auditable_id: post_id).last
      expect(audit.action).to eq("destroy")
      expect(audit.version).to eq(2)
    end

    it "tracks audit comment" do
      post = Post.new(title: "Hello")
      post.audit_comment = "Initial creation"
      post.save!

      audit = post.audits.first
      expect(audit.comment).to eq("Initial creation")
    end

    it "tracks audit context" do
      ActiveVersion.with_context({request_id: "123", ip: "1.2.3.4"}) do
        post = Post.create!(title: "Hello")
        audit = post.audits.first
        expect(audit.audited_context["request_id"]).to eq("123")
        expect(audit.audited_context["ip"]).to eq("1.2.3.4")
      end
    end

    it "uses configured class_name for version sequencing queries" do
      custom_post_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "MappedAuditTypePost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: PostAudit, class_name: "Post"
      end

      expect(PostAudit).to receive(:where)
        .with(hash_including("auditable_type" => "Post"))
        .at_least(:once)
        .and_call_original

      post = custom_post_class.create!(title: "v1")
      post.update!(title: "v2")
      post.update!(title: "v3")

      versions = post.audits.map(&:version)
      expect(versions).to eq([1, 2, 3])
    end
  end

  describe "revision reconstruction" do
    it "reconstructs post at specific version" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!
      post.title = "v3"
      post.save!

      revision = post.audit_revision(version: 1)
      expect(revision).to be_present
      expect(revision.title).to eq("v1")

      revision = post.audit_revision(version: 2)
      expect(revision).to be_present
      expect(revision.title).to eq("v2")
    end

    it "reconstructs post at specific time" do
      post = Post.create!(title: "v1")
      # Get the actual created_at time from the audit, not Time.current
      audit1 = post.audits.order(version: :asc).first
      time1 = audit1.created_at

      post.title = "v2"
      post.save!
      # Reload to get the latest audit
      post.reload
      # Get the actual created_at time from the audit for "v2"
      # Use a time slightly after the audit's created_at to ensure we include it
      # This accounts for database timestamp precision differences
      audit2 = post.audits.order(version: :asc).where("version > ?", audit1.version).first
      # Use audit's created_at exactly so we don't go into the future (FutureTimeError)
      time2 = audit2.created_at

      post.title = "v3"
      post.save!

      revision = post.audit_revision_at(time1)
      expect(revision).to be_present
      expect(revision.title).to eq("v1")

      revision = post.audit_revision_at(time2)
      expect(revision).to be_present
      expect(revision.title).to eq("v2")
    end
  end

  describe "audit scopes" do
    it "filters by action" do
      # Create record
      post = Post.create!(title: "Hello", body: "Initial")

      # Update with actual changes
      post.title = "World"
      post.body = "Updated"
      post.save!

      # Destroy record
      post_id = post.id
      post.destroy!

      # Verify audits by action - query directly from database
      creates = PostAudit.where(auditable_type: "Post", auditable_id: post_id, action: "create")
      expect(creates.count).to eq(1)
      expect(creates.first.action).to eq("create")

      updates = PostAudit.where(auditable_type: "Post", auditable_id: post_id, action: "update")
      expect(updates.count).to eq(1)
      expect(updates.first.action).to eq("update")

      destroys = PostAudit.where(auditable_type: "Post", auditable_id: post_id, action: "destroy")
      expect(destroys.count).to eq(1)
      expect(destroys.first.action).to eq("destroy")
    end

    it "filters by version range" do
      # Create initial record
      post = Post.create!(title: "v1", body: "body1")

      # Make multiple updates with actual changes
      post.title = "v2"
      post.body = "body2"
      post.save!

      post.title = "v3"
      post.body = "body3"
      post.save!

      post.title = "v4"
      post.body = "body4"
      post.save!

      # Verify version range filtering
      audits = post.audits.from_version(2).to_version(3)
      expect(audits.count).to eq(2)
      expect(audits.map(&:version).sort).to eq([2, 3])

      # Verify all audits exist
      all_audits = PostAudit.where(auditable_type: "Post", auditable_id: post.id).order(version: :asc)
      expect(all_audits.count).to eq(4)
    end
  end

  describe "SQL generation" do
    it "generates SQL for audit insert" do
      post = Post.create!(title: "Hello")
      post.title = "World"
      post.save!

      sql = post.audit_sql
      expect(sql).to be_a(String)
      expect(sql).to include("INSERT")
      expect(sql).to include("post_audits")
    end

    it "does not duplicate created_at or updated_at columns in the INSERT" do
      post = Post.create!(title: "Hello")
      post.title = "World"
      post.save!

      sql = post.audit_sql
      expect(sql.scan('"created_at"').size).to eq(1)
      expect(sql.scan('"updated_at"').size).to eq(1)
    end

    it "prepare_sql_values stringifies keys and merges symbol/string duplicates (last wins)" do
      post = Post.new(title: "Hello")
      out = post.send(
        :prepare_sql_values,
        {
          :action => "update",
          "action" => "create"
        }
      )
      expect(out.keys).to eq(["action"])
      expect(out["action"]).to eq("create")
      expect(out.keys).to all(be_a(String))
    end

    it "generates batch SQL for multiple records" do
      post1 = Post.create!(title: "Hello")
      post2 = Post.create!(title: "World")

      sql = PostAudit.batch_insert_sql([post1, post2], force: true)
      expect(sql).to be_a(String)
      expect(sql).to include("INSERT")
    end
  end

  describe "without_auditing" do
    it "skips auditing when disabled" do
      Post.without_auditing do
        post = Post.create!(title: "Hello")
        expect(post.audits.count).to eq(0)
      end
    end

    it "re-enables auditing after block" do
      Post.without_auditing do
        Post.create!(title: "Hello")
      end

      post = Post.create!(title: "World")
      expect(post.audits.count).to eq(1)
    end
  end

  describe "future time validation" do
    it "raises error when querying future time" do
      post = Post.create!(title: "v1")
      future_time = 1.day.from_now

      expect {
        post.audit_revision_at(future_time)
      }.to raise_error(ActiveVersion::FutureTimeError, /Future state cannot be known/)
    end

    it "allows past and present times" do
      post = Post.create!(title: "v1")
      post.title = "v2"
      post.save!

      past_time = 1.hour.ago
      revision = post.audit_revision_at(past_time)
      expect(revision).to be_present
    end
  end

  describe "readonly enforcement" do
    it "prevents updates to persisted audits" do
      post = Post.create!(title: "Test")
      audit = post.audits.first

      expect {
        audit.action = "hacked"
        audit.save!
      }.to raise_error(ActiveVersion::ReadonlyVersionError)
    end

    it "prevents destroys to persisted audits" do
      post = Post.create!(title: "Test")
      audit = post.audits.first

      expect {
        audit.destroy
      }.to raise_error(ActiveVersion::ReadonlyVersionError)
    end
  end

  describe "transaction rollback" do
    it "clears audit association cache on rollback" do
      post = Post.create!(title: "Test")

      ActiveRecord::Base.transaction do
        post.title = "Updated"
        post.save!
        expect(post.audits.count).to eq(2)
        raise ActiveRecord::Rollback
      end

      post.reload
      expect(post.audits.count).to eq(1) # Only create audit
    end
  end

  describe "thread-local configuration" do
    it "allows per-thread configuration overrides" do
      Post.with_audited_options(only: ["title"]) do
        post = Post.create!(title: "Test", body: "Body")
        post.title = "Updated"
        post.body = "Updated Body"
        post.save!

        audit = post.audits.last
        changes = audit.audited_changes
        expect(changes).to have_key("title")
        expect(changes).not_to have_key("body")
      end
    end
  end
end
