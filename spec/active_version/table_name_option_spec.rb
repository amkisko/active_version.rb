require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "has_* table_name option" do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  it "applies table_name for has_translations" do
    translation_class = Class.new(ApplicationRecord) do
      self.table_name = "post_translations"
      include ActiveVersion::Translations::TranslationRecord
    end
    stub_const("TableNameOptionTranslationPostTranslation", translation_class)

    model_class = Class.new(ApplicationRecord) { self.table_name = "posts" }
    stub_const("TableNameOptionTranslationPost", model_class)
    TableNameOptionTranslationPost.has_translations(table_name: "custom_post_translations")

    expect(TableNameOptionTranslationPost.translation_class.table_name).to eq("custom_post_translations")
    config = ActiveVersion.registry.config_for(TableNameOptionTranslationPost, :translations)
    expect(config[:table_name]).to eq("custom_post_translations")
  end

  it "applies table_name for has_revisions" do
    revision_class = Class.new(ApplicationRecord) do
      self.table_name = "post_revisions"
      include ActiveVersion::Revisions::RevisionRecord
    end
    stub_const("TableNameOptionRevisionPostRevision", revision_class)

    model_class = Class.new(ApplicationRecord) { self.table_name = "posts" }
    stub_const("TableNameOptionRevisionPost", model_class)
    TableNameOptionRevisionPost.has_revisions(table_name: "custom_post_revisions", auto: false)

    expect(TableNameOptionRevisionPost.revision_class.table_name).to eq("custom_post_revisions")
    config = ActiveVersion.registry.config_for(TableNameOptionRevisionPost, :revisions)
    expect(config[:table_name]).to eq("custom_post_revisions")
  end

  it "applies table_name for has_audits" do
    audit_class = Class.new(ApplicationRecord) do
      self.table_name = "post_audits"
      include ActiveVersion::Audits::AuditRecord
    end
    stub_const("TableNameOptionAuditPostAudit", audit_class)

    model_class = Class.new(ApplicationRecord) { self.table_name = "posts" }
    stub_const("TableNameOptionAuditPost", model_class)
    TableNameOptionAuditPost.has_audits(
      as: TableNameOptionAuditPostAudit,
      table_name: "custom_post_audits",
      auto: false
    )

    expect(TableNameOptionAuditPost.audit_class.table_name).to eq("custom_post_audits")
    config = ActiveVersion.registry.config_for(TableNameOptionAuditPost, :audits)
    expect(config[:table_name]).to eq("custom_post_audits")
  end

  it "ignores per-model shard option for has_audits" do
    audit_class = Class.new(ApplicationRecord) do
      self.table_name = "post_audits"
      include ActiveVersion::Audits::AuditRecord
    end
    stub_const("TableNameOptionShardPostAudit", audit_class)

    model_class = Class.new(ApplicationRecord) { self.table_name = "posts" }
    stub_const("TableNameOptionShardPost", model_class)
    TableNameOptionShardPost.has_audits(
      as: TableNameOptionShardPostAudit,
      shard: :audit_db,
      auto: false
    )

    config = ActiveVersion.registry.config_for(TableNameOptionShardPost, :audits)
    expect(config[:shard]).to be_nil
  end

  it "ignores per-model shard option for has_revisions" do
    revision_class = Class.new(ApplicationRecord) do
      self.table_name = "post_revisions"
      include ActiveVersion::Revisions::RevisionRecord
    end
    stub_const("TableNameOptionRevisionShardPostRevision", revision_class)

    model_class = Class.new(ApplicationRecord) { self.table_name = "posts" }
    stub_const("TableNameOptionRevisionShardPost", model_class)
    TableNameOptionRevisionShardPost.has_revisions(shard: :revision_db, auto: false)

    config = ActiveVersion.registry.config_for(TableNameOptionRevisionShardPost, :revisions)
    expect(config[:shard]).to be_nil
  end
end
