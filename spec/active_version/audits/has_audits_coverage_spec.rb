require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion::Audits::HasAudits coverage" do
  before(:all) do
    DatabaseHelper.setup

    Object.const_set("CommentedPost", Class.new(ApplicationRecord) do
      self.table_name = "posts"
      include ActiveVersion::Audits::HasAudits
      has_audits as: PostAudit, class_name: "CommentedPost", comment_required: true
    end)

    Object.const_set("AliasAuditedPost", Class.new(ApplicationRecord) do
      self.table_name = "posts"
      include ActiveVersion::Audits::HasAudits
      has_audits as: PostAudit, class_name: "Post"
    end)

    Object.const_set("UpdatableAuditPost", Class.new(ApplicationRecord) do
      self.table_name = "posts"
      include ActiveVersion::Audits::HasAudits
      has_audits as: PostAudit, class_name: "UpdatableAuditPost"
    end)
  end

  after(:all) do
    [:CommentedPost, :AliasAuditedPost, :UpdatableAuditPost].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
    ActiveVersion.clear_context!
    ActiveVersion.auditing_enabled = true
  end

  it "normalizes and restores thread-local options in with_audited_options" do
    key = Post.send(:audited_current_options_key)
    original = ActiveVersion.store_get(key)
    opts = Struct.new(:to_h).new({"only" => [:title], "max_audits" => 5, "on" => [:update]})

    Post.with_audited_options(opts) do
      expect(Post.audited_options[:only]).to eq(["title"])
      expect(Post.audited_options[:max_audits]).to eq(5)
      expect(Post.audited_options[:on]).to eq([:update])
    end

    expect(ActiveVersion.store_get(key)).to eq(original)
  end

  it "toggles class auditing via without_auditing/with_auditing" do
    expect(Post.class_auditing_enabled?).to be(true)

    Post.without_auditing do
      expect(Post.class_auditing_enabled?).to be(false)
    end

    Post.send(:disable_auditing)
    Post.with_auditing do
      expect(Post.class_auditing_enabled?).to be(true)
    end
    expect(Post.class_auditing_enabled?).to be(false)
    Post.send(:enable_auditing)
  end

  it "handles run_conditional_check proc, symbol, and fallback" do
    post = Post.new
    allow(post).to receive(:custom_condition).and_return(true)

    expect(post.send(:run_conditional_check, ->(_record) { true })).to be(true)
    expect(post.send(:run_conditional_check, :custom_condition)).to be(true)
    expect(post.send(:run_conditional_check, :missing_method)).to be(true)
    expect(post.send(:run_conditional_check, ->(_record) { false }, matching: false)).to be(true)
  end

  it "applies comment-required validation paths" do
    record = CommentedPost.new(title: "draft")
    expect(record.send(:comment_required_state?)).to be(true)
    expect { record.send(:require_comment) }.to throw_symbol(:abort)

    record.audit_comment = "ok"
    expect { record.send(:require_comment) }.not_to throw_symbol
  end

  it "uses class_name override for audits relation when auditable_type differs" do
    post = Post.create!(title: "base")
    post.update!(title: "updated")

    aliased = AliasAuditedPost.find(post.id)
    relation = aliased.audits

    expect(relation.to_sql).to include("auditable_type")
    expect(relation.to_sql).to include("Post")
    expect(relation.first).to be_a(PostAudit)
  end

  it "filters combined audits in active_audits" do
    post = Post.create!(title: "v1")
    post.update!(title: "v2")
    first_audit_id = post.audits.first.id

    PostAudit.connection.execute("UPDATE post_audits SET audited_changes = '{}' WHERE id = #{first_audit_id}")

    active = post.send(:active_audits)
    expect(active.map(&:id)).not_to include(first_audit_id)
  end

  it "updates audited options when has_audits is called again" do
    UpdatableAuditPost.has_audits only: [:title], max_audits: 3
    expect(UpdatableAuditPost.audited_options[:only]).to eq(["title"])
    expect(UpdatableAuditPost.audited_options[:max_audits]).to eq(3)
  end

  it "covers class-level revision helper methods" do
    post = Post.create!(title: "v1")
    post.update!(title: "v2")
    post.update!(title: "v3")

    expect { Post.revisions(2) }.to raise_error(NameError)
  end

  it "covers revision_with and association proxy cleanup helpers" do
    revision = Post.send(:revision_with, {"title" => "snapshot"}, id: 12)
    proxy = double("association_proxy")
    allow(proxy).to receive(:proxy_respond_to?).and_return(true)
    revision.instance_variable_set(:@fake_proxy, proxy)

    Post.send(:clear_association_proxies, revision)

    expect(revision).to be_readonly
    expect(revision.id).to eq(12)
    expect(revision.instance_variable_get(:@fake_proxy)).to be_nil
  end

  it "covers apply_audit_table_name! when custom table name is present" do
    klass = Class.new do
      class << self
        attr_accessor :table_name
      end
    end

    allow(Post).to receive(:audited_options).and_return({table_name: "custom_post_audits"})
    Post.send(:apply_audit_table_name!, klass)
    expect(klass.table_name).to eq("custom_post_audits")
  end

  it "resolves audit_class from :as string and via superclass" do
    Object.const_set("BaseAuditedPost", Class.new(ApplicationRecord) do
      self.table_name = "posts"
      include ActiveVersion::Audits::HasAudits
      has_audits as: "PostAudit", class_name: "BaseAuditedPost"
    end)

    Object.const_set("ChildAuditedPost", Class.new(BaseAuditedPost))
    expect(BaseAuditedPost.audit_class).to eq(PostAudit)
    expect(ChildAuditedPost.audit_class).to eq(PostAudit)
  ensure
    Object.send(:remove_const, :ChildAuditedPost) if Object.const_defined?(:ChildAuditedPost)
    Object.send(:remove_const, :BaseAuditedPost) if Object.const_defined?(:BaseAuditedPost)
  end

  it "raises configuration error when dynamic class omits class_name" do
    expect do
      Class.new(ApplicationRecord) do
        self.table_name = "posts"
        include ActiveVersion::Audits::HasAudits
        has_audits as: PostAudit
      end
    end.to raise_error(ActiveVersion::ConfigurationError, /must specify class_name option/)
  end

  it "falls back to table-name derived audit class resolution" do
    klass = Class.new(ApplicationRecord) do
      self.table_name = "posts"
      include ActiveVersion::Audits::HasAudits
      has_audits class_name: "GhostPost"
    end

    expect(klass.audit_class).to eq(PostAudit)
  end

  it "handles non-hash options and unknown keys in with_audited_options" do
    Post.with_audited_options("not-a-hash") do
      expect(Post.audited_options).to be_a(Hash)
    end

    Post.with_audited_options(custom_runtime_flag: true) do
      expect(Post.audited_options[:custom_runtime_flag]).to eq(true)
    end
  end

  it "covers instance-level audit_sql actions and helper wrappers" do
    post = Post.new(title: "new")
    expect(post.audit_sql).to include("create")

    post.save!
    post.title = "updated"
    expect(post.audit_sql).to include("update")
    expect(post.audit_sql(destroy: true)).to include("destroy")

    expect(post.without_auditing { true }).to eq(true)
    expect(post.with_auditing { true }).to eq(true)
  end

  it "covers instance-level revision_with implementation" do
    post = Post.create!(title: "v1")
    revision = post.send(:revision_with, {"title" => "snap"})

    expect(revision).to be_readonly
    expect(revision.id).to eq(post.id)
    expect(revision.title).to eq("snap")
    expect(revision).to be_new_record
  end
end
