require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe ActiveVersion::Query do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
    PostRevision.destroy_all
    PostTranslation.destroy_all
    ActiveVersion::Runtime.reset_adapter!
  end

  describe ".audits" do
    it "returns a relation on the default shard" do
      post = Post.create!(title: "Hello")
      result = described_class.audits(post)

      expect(result).to be_a(ActiveRecord::Relation)
      expect(result.first).to be_a(PostAudit)
    end

    it "returns relation results without internal shard materialization" do
      post = Post.create!(title: "Hello")

      result = described_class.audits(post)
      expect(result).to be_a(ActiveRecord::Relation)
      expect(result.first).to be_a(PostAudit)
    end

    it "falls back to record.id when custom audit identity method is unavailable" do
      plain_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name = "PlainQueryPost"
        def self.audit_class = PostAudit
      end

      plain = plain_class.create!(title: "Hello")
      PostAudit.create!(
        auditable_type: plain_class.name,
        auditable_id: plain.id,
        action: "create",
        version: 1,
        audited_changes: {}
      )

      result = described_class.audits(plain)
      expect(result.count).to eq(1)
    end

    it "uses active_version_audit_identity_map when provided" do
      relation = PostAudit.none
      audit_class = class_double("InlineAuditClass")
      record_class = Class.new
      record_class.define_singleton_method(:name) { "InlineAuditRecord" }
      record_class.define_singleton_method(:audit_class) { audit_class }
      record_class.define_singleton_method(:primary_key) { "id" }
      Object.const_set("InlineAuditRecord", record_class)

      record = record_class.allocate
      record.define_singleton_method(:active_version_audit_identity_map) { {"auditable_id" => "ext-audit-1"} }

      allow(ActiveVersion.column_mapper).to receive(:column_for).with(record_class, :audits, :auditable).and_return(:auditable)
      captured_where = nil
      allow(audit_class).to receive(:where) { |where_args| captured_where = where_args; relation }

      expect(described_class.audits(record)).to eq(relation)
      expect(captured_where).to eq("auditable_type" => "InlineAuditRecord", "auditable_id" => "ext-audit-1")
    ensure
      Object.send(:remove_const, "InlineAuditRecord") if Object.const_defined?("InlineAuditRecord")
    end

    it "falls back to composite primary keys when no audit identity helpers are available" do
      relation = PostAudit.none
      audit_class = class_double("InlineCompositeAuditClass")
      record_class = Class.new
      record_class.define_singleton_method(:name) { "InlineCompositeAuditRecord" }
      record_class.define_singleton_method(:audit_class) { audit_class }
      record_class.define_singleton_method(:primary_key) { [:tenant_id, :external_id] }
      Object.const_set("InlineCompositeAuditRecord", record_class)

      record = record_class.allocate
      values = {"tenant_id" => 11, "external_id" => "post-11"}
      record.define_singleton_method(:[]) { |column| values[column.to_s] }
      record.define_singleton_method(:id) { nil }

      allow(ActiveVersion.column_mapper).to receive(:column_for).with(record_class, :audits, :auditable).and_return(:auditable)
      captured_where = nil
      allow(audit_class).to receive(:where) { |where_args| captured_where = where_args; relation }

      expect(described_class.audits(record)).to eq(relation)
      expect(captured_where).to eq("auditable_type" => "InlineCompositeAuditRecord", "tenant_id" => 11, "external_id" => "post-11")
    ensure
      Object.send(:remove_const, "InlineCompositeAuditRecord") if Object.const_defined?("InlineCompositeAuditRecord")
    end
  end

  describe ".translations" do
    it "returns relation results without internal shard materialization" do
      post = Post.create!(title: "Hello")
      post.translations.create!(locale: "fi", title: "Moi")
      allow(ActiveVersion.column_mapper).to receive(:column_for).and_call_original
      allow(ActiveVersion.column_mapper).to receive(:column_for).with(Post, :translations, :locale).and_return(:locale)

      result = described_class.translations(post, locale: "fi")
      expect(result).to be_a(ActiveRecord::Relation)
      expect(result.first).to be_a(PostTranslation)
    end

    it "falls back to record.id when custom translation foreign key resolver is unavailable" do
      plain_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name = "PlainTranslationQueryPost"
        def self.translation_class = PostTranslation
      end

      plain = plain_class.create!(title: "Hello")
      PostTranslation.create!(post_id: plain.id, locale: "fi", title: "Moi")

      result = described_class.translations(plain, locale: "fi")
      expect(result.count).to eq(1)
    end

    it "uses active_version_translation_identity_map when provided" do
      relation = PostTranslation.none
      translation_class = class_double("InlineTranslationClass")
      record_class = Class.new
      record_class.define_singleton_method(:name) { "InlineTranslationRecord" }
      record_class.define_singleton_method(:translation_class) { translation_class }
      record_class.define_singleton_method(:primary_key) { "id" }
      Object.const_set("InlineTranslationRecord", record_class)

      record = record_class.allocate
      record.define_singleton_method(:active_version_translation_identity_map) { {"record_uuid" => "ext-tr-1"} }

      allow(translation_class).to receive(:source_foreign_key).and_return("record_uuid")
      captured_where = nil
      allow(translation_class).to receive(:where) { |where_args| captured_where = where_args; relation }
      expect(described_class.translations(record)).to eq(relation)
      expect(captured_where).to eq("record_uuid" => "ext-tr-1")
    ensure
      Object.send(:remove_const, "InlineTranslationRecord") if Object.const_defined?("InlineTranslationRecord")
    end

    it "falls back to composite primary keys for translations when no helper is available" do
      relation = PostTranslation.none
      translation_class = class_double("InlineCompositeTranslationClass")
      record_class = Class.new
      record_class.define_singleton_method(:name) { "InlineCompositeTranslationRecord" }
      record_class.define_singleton_method(:translation_class) { translation_class }
      record_class.define_singleton_method(:primary_key) { [:tenant_id, :external_id] }
      Object.const_set("InlineCompositeTranslationRecord", record_class)

      record = record_class.allocate
      values = {"tenant_id" => 9, "external_id" => "tr-9"}
      record.define_singleton_method(:[]) { |column| values[column.to_s] }
      record.define_singleton_method(:id) { nil }

      allow(translation_class).to receive(:source_foreign_key).and_return([:tenant_id, :external_id])
      captured_where = nil
      allow(translation_class).to receive(:where) { |where_args| captured_where = where_args; relation }
      expect(described_class.translations(record)).to eq(relation)
      expect(captured_where).to eq("tenant_id" => 9, "external_id" => "tr-9")
    ensure
      Object.send(:remove_const, "InlineCompositeTranslationRecord") if Object.const_defined?("InlineCompositeTranslationRecord")
    end
  end

  describe ".revisions" do
    it "returns relation results without internal shard materialization" do
      post = Post.create!(title: "v1")
      post.update!(title: "v2")

      result = described_class.revisions(post)
      expect(result).to be_a(ActiveRecord::Relation)
      expect(result.first).to be_a(PostRevision)
    end

    it "falls back to record.id and applies explicit version filter when resolver is unavailable" do
      plain_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name = "PlainRevisionQueryPost"
        def self.revision_class = PostRevision
      end

      plain = plain_class.create!(title: "v1")
      PostRevision.create!(post_id: plain.id, version: 1, title: "v1")
      PostRevision.create!(post_id: plain.id, version: 2, title: "v2")

      result = described_class.revisions(plain, version: 2)
      expect(result.map(&:version)).to eq([2])
    end

    it "uses active_version_revision_identity_map when provided" do
      relation = PostRevision.none
      ordered_relation = PostRevision.none
      revision_class = class_double("InlineRevisionClass")
      record_class = Class.new
      record_class.define_singleton_method(:name) { "InlineRevisionRecord" }
      record_class.define_singleton_method(:revision_class) { revision_class }
      record_class.define_singleton_method(:primary_key) { "id" }
      Object.const_set("InlineRevisionRecord", record_class)

      record = record_class.allocate
      record.define_singleton_method(:active_version_revision_identity_map) { {"record_uuid" => "ext-rv-1"} }

      allow(revision_class).to receive(:source_foreign_key).and_return("record_uuid")
      captured_where = nil
      allow(revision_class).to receive(:where) { |where_args| captured_where = where_args; relation }
      allow(relation).to receive(:order).with(version: :asc).and_return(ordered_relation)
      allow(ActiveVersion.column_mapper).to receive(:column_for).with(record_class, :revisions, :version).and_return(:version)
      expect(described_class.revisions(record)).to eq(ordered_relation)
      expect(captured_where).to eq("record_uuid" => "ext-rv-1")
    ensure
      Object.send(:remove_const, "InlineRevisionRecord") if Object.const_defined?("InlineRevisionRecord")
    end

    it "falls back to composite primary keys for revisions when no helper is available" do
      relation = PostRevision.none
      ordered_relation = PostRevision.none
      revision_class = class_double("InlineCompositeRevisionClass")
      record_class = Class.new
      record_class.define_singleton_method(:name) { "InlineCompositeRevisionRecord" }
      record_class.define_singleton_method(:revision_class) { revision_class }
      record_class.define_singleton_method(:primary_key) { [:tenant_id, :external_id] }
      Object.const_set("InlineCompositeRevisionRecord", record_class)

      record = record_class.allocate
      values = {"tenant_id" => 15, "external_id" => "rv-15"}
      record.define_singleton_method(:[]) { |column| values[column.to_s] }
      record.define_singleton_method(:id) { nil }

      allow(revision_class).to receive(:source_foreign_key).and_return([:tenant_id, :external_id])
      captured_where = nil
      allow(revision_class).to receive(:where) { |where_args| captured_where = where_args; relation }
      allow(relation).to receive(:order).with(version: :asc).and_return(ordered_relation)
      allow(ActiveVersion.column_mapper).to receive(:column_for).with(record_class, :revisions, :version).and_return(:version)
      expect(described_class.revisions(record)).to eq(ordered_relation)
      expect(captured_where).to eq("tenant_id" => 15, "external_id" => "rv-15")
    ensure
      Object.send(:remove_const, "InlineCompositeRevisionRecord") if Object.const_defined?("InlineCompositeRevisionRecord")
    end
  end

  describe ".current_transaction" do
    it "queries transaction id on PostgreSQL adapter" do
      connection = instance_double("Connection", adapter_name: "PostgreSQL")
      allow(connection).to receive(:execute).with("SELECT pg_current_xact_id()").and_return([["42"]])
      runtime_adapter = instance_double("RuntimeAdapter", base_connection: connection)
      allow(runtime_adapter).to receive(:supports_current_transaction_id?).with(connection).and_return(true)
      allow(ActiveVersion::Runtime).to receive(:adapter).and_return(runtime_adapter)

      expect(described_class.current_transaction).to eq("42")
    end
  end
end
