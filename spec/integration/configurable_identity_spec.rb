require "spec_helper"
require "support/database"
require "support/integration_helpers"

RSpec.describe "ActiveVersion configurable identity strategy", type: :integration do
  include IntegrationHelpers

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

  it "supports custom revision foreign key column and value resolver" do
    conn = ActiveRecord::Base.connection
    conn.create_table :custom_source_posts, force: true do |t|
      t.string :external_id, null: false
      t.string :title
      t.timestamps
    end

    conn.create_table :custom_source_post_revisions, force: true do |t|
      t.string :record_uuid, null: false
      t.integer :version, null: false
      t.string :title
      t.timestamps
    end
    conn.add_index :custom_source_post_revisions, [:record_uuid, :version], unique: true

    revision_class = Class.new(ApplicationRecord) do
      self.table_name = "custom_source_post_revisions"
      include ActiveVersion::Revisions::RevisionRecord

      def self.name = "CustomSourcePostRevision"
    end
    Object.const_set("CustomSourcePostRevision", revision_class)

    post_class = Class.new(ApplicationRecord) do
      self.table_name = "custom_source_posts"
      include ActiveVersion::Revisions::HasRevisions

      def self.name = "CustomSourcePost"

      has_revisions as: CustomSourcePostRevision, foreign_key: :record_uuid, identity_resolver: :external_id
    end
    Object.const_set("CustomSourcePost", post_class)
    CustomSourcePostRevision.setup_associations if CustomSourcePostRevision.respond_to?(:setup_associations)

    post = CustomSourcePost.create!(external_id: "ext-post-1", title: "v1")
    post.update!(title: "v2")

    expect(post.revisions.count).to eq(1)
    expect(post.revisions.first.record_uuid).to eq("ext-post-1")
    expect(CustomSourcePostRevision.source_foreign_key).to eq("record_uuid")
    expect(ActiveVersion::Query.revisions(post).count).to eq(1)
  ensure
    Object.send(:remove_const, "CustomSourcePost") if Object.const_defined?("CustomSourcePost")
    Object.send(:remove_const, "CustomSourcePostRevision") if Object.const_defined?("CustomSourcePostRevision")
    conn.drop_table(:custom_source_post_revisions, if_exists: true) if conn.data_source_exists?(:custom_source_post_revisions)
    conn.drop_table(:custom_source_posts, if_exists: true) if conn.data_source_exists?(:custom_source_posts)
  end

  it "supports custom translation foreign key column name" do
    conn = ActiveRecord::Base.connection
    conn.create_table :custom_locale_posts, force: true do |t|
      t.string :title
      t.timestamps
    end

    conn.create_table :custom_locale_post_translations, force: true do |t|
      t.integer :record_uuid, null: false
      t.string :locale, null: false
      t.string :title
      t.timestamps
    end
    conn.add_index :custom_locale_post_translations, [:record_uuid, :locale], unique: true

    translation_class = Class.new(ApplicationRecord) do
      self.table_name = "custom_locale_post_translations"
      include ActiveVersion::Translations::TranslationRecord

      def self.name = "CustomLocalePostTranslation"
    end
    Object.const_set("CustomLocalePostTranslation", translation_class)

    post_class = Class.new(ApplicationRecord) do
      self.table_name = "custom_locale_posts"
      include ActiveVersion::Translations::HasTranslations

      def self.name = "CustomLocalePost"

      has_translations foreign_key: :record_uuid
    end
    Object.const_set("CustomLocalePost", post_class)
    CustomLocalePostTranslation.setup_associations if CustomLocalePostTranslation.respond_to?(:setup_associations)

    post = CustomLocalePost.create!(title: "hello")
    translation = post.translations.create!(locale: "fi", title: "hei")

    expect(translation.record_uuid).to eq(post.id)
    expect(CustomLocalePostTranslation.source_foreign_key).to eq("record_uuid")
    expect(ActiveVersion::Query.translations(post, locale: "fi").count).to eq(1)
  ensure
    Object.send(:remove_const, "CustomLocalePost") if Object.const_defined?("CustomLocalePost")
    Object.send(:remove_const, "CustomLocalePostTranslation") if Object.const_defined?("CustomLocalePostTranslation")
    conn.drop_table(:custom_locale_post_translations, if_exists: true) if conn.data_source_exists?(:custom_locale_post_translations)
    conn.drop_table(:custom_locale_posts, if_exists: true) if conn.data_source_exists?(:custom_locale_posts)
  end

  it "supports custom audit identity resolver for auditable_id" do
    conn = ActiveRecord::Base.connection
    conn.create_table :custom_trace_posts, force: true do |t|
      t.string :external_id, null: false
      t.string :title
      t.timestamps
    end

    conn.create_table :custom_trace_post_audits, force: true do |t|
      t.string :auditable_type, null: false
      t.string :auditable_id, null: false
      t.string :action, null: false
      t.integer :version, null: false
      t.text :audited_changes
      t.timestamps
    end
    conn.add_index :custom_trace_post_audits, [:auditable_type, :auditable_id, :version], unique: true, name: "idx_custom_trace_audit_uniqueness"

    audit_class = Class.new(ApplicationRecord) do
      self.table_name = "custom_trace_post_audits"
      include ActiveVersion::Audits::AuditRecord

      def self.name = "CustomTracePostAudit"
    end
    Object.const_set("CustomTracePostAudit", audit_class)

    post_class = Class.new(ApplicationRecord) do
      self.table_name = "custom_trace_posts"
      include ActiveVersion::Audits::HasAudits

      def self.name = "CustomTracePost"

      has_audits as: CustomTracePostAudit, identity_resolver: :external_id
    end
    Object.const_set("CustomTracePost", post_class)
    CustomTracePostAudit.setup_associations if CustomTracePostAudit.respond_to?(:setup_associations)

    post = CustomTracePost.create!(external_id: "audit-ext-1", title: "v1")
    post.update!(title: "v2")

    latest = post.audits.order(version: :desc).first
    expect(latest.auditable_id).to eq("audit-ext-1")
    expect(ActiveVersion::Query.audits(post).count).to eq(2)
  ensure
    Object.send(:remove_const, "CustomTracePost") if Object.const_defined?("CustomTracePost")
    Object.send(:remove_const, "CustomTracePostAudit") if Object.const_defined?("CustomTracePostAudit")
    conn.drop_table(:custom_trace_post_audits, if_exists: true) if conn.data_source_exists?(:custom_trace_post_audits)
    conn.drop_table(:custom_trace_posts, if_exists: true) if conn.data_source_exists?(:custom_trace_posts)
  end

  it "supports string identity_resolver and exposes primary_key wiring for revisions" do
    conn = ActiveRecord::Base.connection
    conn.create_table :string_key_posts, force: true do |t|
      t.string :external_id, null: false
      t.string :title
      t.timestamps
    end

    conn.create_table :string_key_post_revisions, force: true do |t|
      t.string :record_uuid, null: false
      t.integer :version, null: false
      t.string :title
      t.timestamps
    end
    conn.add_index :string_key_post_revisions, [:record_uuid, :version], unique: true

    revision_class = Class.new(ApplicationRecord) do
      self.table_name = "string_key_post_revisions"
      include ActiveVersion::Revisions::RevisionRecord

      def self.name = "StringKeyPostRevision"
    end
    Object.const_set("StringKeyPostRevision", revision_class)

    post_class = Class.new(ApplicationRecord) do
      self.table_name = "string_key_posts"
      include ActiveVersion::Revisions::HasRevisions

      def self.name = "StringKeyPost"

      has_revisions as: StringKeyPostRevision, foreign_key: :record_uuid, identity_resolver: "external_id"
    end
    Object.const_set("StringKeyPost", post_class)
    StringKeyPostRevision.setup_associations(force: true) if StringKeyPostRevision.respond_to?(:setup_associations)

    expect(StringKeyPost.reflect_on_association(:revisions).options[:primary_key]).to eq("external_id")
    expect(StringKeyPostRevision.reflect_on_association(:string_key_post).options[:primary_key]).to eq("external_id")
    expect(ActiveVersion.registry.config_for_model_name("StringKeyPost", :revisions)[:foreign_key]).to eq("record_uuid")
  ensure
    Object.send(:remove_const, "StringKeyPost") if Object.const_defined?("StringKeyPost")
    Object.send(:remove_const, "StringKeyPostRevision") if Object.const_defined?("StringKeyPostRevision")
    conn.drop_table(:string_key_post_revisions, if_exists: true) if conn.data_source_exists?(:string_key_post_revisions)
    conn.drop_table(:string_key_posts, if_exists: true) if conn.data_source_exists?(:string_key_posts)
  end

  it "supports string identity_resolver and exposes primary_key wiring for translations" do
    conn = ActiveRecord::Base.connection
    conn.create_table :string_locale_posts, force: true do |t|
      t.string :external_id, null: false
      t.string :title
      t.timestamps
    end

    conn.create_table :string_locale_post_translations, force: true do |t|
      t.string :record_uuid, null: false
      t.string :locale, null: false
      t.string :title
      t.timestamps
    end
    conn.add_index :string_locale_post_translations, [:record_uuid, :locale], unique: true

    translation_class = Class.new(ApplicationRecord) do
      self.table_name = "string_locale_post_translations"
      include ActiveVersion::Translations::TranslationRecord

      def self.name = "StringLocalePostTranslation"
    end
    Object.const_set("StringLocalePostTranslation", translation_class)

    post_class = Class.new(ApplicationRecord) do
      self.table_name = "string_locale_posts"
      include ActiveVersion::Translations::HasTranslations

      def self.name = "StringLocalePost"

      has_translations foreign_key: :record_uuid, identity_resolver: "external_id"
    end
    Object.const_set("StringLocalePost", post_class)
    StringLocalePostTranslation.setup_associations(force: true) if StringLocalePostTranslation.respond_to?(:setup_associations)

    expect(StringLocalePost.reflect_on_association(:translations).options[:primary_key]).to eq("external_id")
    expect(StringLocalePostTranslation.reflect_on_association(:string_locale_post).options[:primary_key]).to eq("external_id")
    expect(ActiveVersion.registry.config_for_model_name("StringLocalePost", :translations)[:foreign_key]).to eq("record_uuid")
  ensure
    Object.send(:remove_const, "StringLocalePost") if Object.const_defined?("StringLocalePost")
    Object.send(:remove_const, "StringLocalePostTranslation") if Object.const_defined?("StringLocalePostTranslation")
    conn.drop_table(:string_locale_post_translations, if_exists: true) if conn.data_source_exists?(:string_locale_post_translations)
    conn.drop_table(:string_locale_posts, if_exists: true) if conn.data_source_exists?(:string_locale_posts)
  end

  it "supports composite identity across revisions, translations, audits, and query helpers" do
    conn = ActiveRecord::Base.connection
    conn.create_table :composite_identity_posts, id: false, force: true do |t|
      t.integer :tenant_id, null: false
      t.string :external_id, null: false
      t.string :title
      t.timestamps
    end
    conn.add_index :composite_identity_posts, [:tenant_id, :external_id], unique: true

    conn.create_table :composite_identity_post_revisions, force: true do |t|
      t.integer :tenant_id, null: false
      t.string :external_id, null: false
      t.integer :version, null: false
      t.string :title
      t.timestamps
    end
    conn.add_index :composite_identity_post_revisions, [:tenant_id, :external_id, :version], unique: true, name: "idx_comp_identity_revision_unique"

    conn.create_table :composite_identity_post_translations, force: true do |t|
      t.integer :tenant_id, null: false
      t.string :external_id, null: false
      t.string :locale, null: false
      t.string :title
      t.timestamps
    end
    conn.add_index :composite_identity_post_translations, [:tenant_id, :external_id, :locale], unique: true, name: "idx_comp_identity_translation_unique"

    conn.create_table :composite_identity_post_audits, force: true do |t|
      t.string :auditable_type, null: false
      t.integer :auditable_tenant_id, null: false
      t.string :auditable_external_id, null: false
      t.string :action, null: false
      t.integer :version, null: false
      t.text :audited_changes
      t.timestamps
    end
    conn.add_index :composite_identity_post_audits, [:auditable_type, :auditable_tenant_id, :auditable_external_id, :version], unique: true, name: "idx_comp_identity_audit_unique"

    revision_class = Class.new(ApplicationRecord) do
      self.table_name = "composite_identity_post_revisions"
      include ActiveVersion::Revisions::RevisionRecord

      def self.name = "CompositeIdentityPostRevision"
    end
    Object.const_set("CompositeIdentityPostRevision", revision_class)

    translation_class = Class.new(ApplicationRecord) do
      self.table_name = "composite_identity_post_translations"
      include ActiveVersion::Translations::TranslationRecord

      def self.name = "CompositeIdentityPostTranslation"
    end
    Object.const_set("CompositeIdentityPostTranslation", translation_class)

    audit_class = Class.new(ApplicationRecord) do
      self.table_name = "composite_identity_post_audits"
      include ActiveVersion::Audits::AuditRecord

      def self.name = "CompositeIdentityPostAudit"
    end
    Object.const_set("CompositeIdentityPostAudit", audit_class)

    post_class = Class.new(ApplicationRecord) do
      self.table_name = "composite_identity_posts"
      self.primary_key = [:tenant_id, :external_id]
      include ActiveVersion::Translations::HasTranslations
      include ActiveVersion::Revisions::HasRevisions
      include ActiveVersion::Audits::HasAudits

      def self.name = "CompositeIdentityPost"

      has_translations as: CompositeIdentityPostTranslation, foreign_key: [:tenant_id, :external_id], identity_resolver: [:tenant_id, :external_id]
      has_revisions as: CompositeIdentityPostRevision, foreign_key: [:tenant_id, :external_id], identity_resolver: [:tenant_id, :external_id]
      has_audits as: CompositeIdentityPostAudit, identity_columns: [:auditable_tenant_id, :auditable_external_id], identity_resolver: [:tenant_id, :external_id], class_name: "CompositeIdentityPost"
    end
    Object.const_set("CompositeIdentityPost", post_class)

    CompositeIdentityPostRevision.setup_associations(force: true) if CompositeIdentityPostRevision.respond_to?(:setup_associations)
    CompositeIdentityPostTranslation.setup_associations(force: true) if CompositeIdentityPostTranslation.respond_to?(:setup_associations)
    CompositeIdentityPostAudit.setup_associations if CompositeIdentityPostAudit.respond_to?(:setup_associations)

    post = CompositeIdentityPost.create!(tenant_id: 7, external_id: "post-7", title: "v1")
    post.update!(title: "v2")
    post.translations.create!(tenant_id: 7, external_id: "post-7", locale: "fi", title: "Moi")

    expect(post.revisions.count).to be >= 1
    expect(post.translations.count).to eq(2)
    expect(post.audits.count).to be >= 2
    expect(post.audits.last.auditable_tenant_id).to eq(7)
    expect(post.audits.last.auditable_external_id).to eq("post-7")

    expect(ActiveVersion::Query.revisions(post).count).to eq(post.revisions.count)
    expect(ActiveVersion::Query.translations(post, locale: "fi").count).to eq(1)
    expect(ActiveVersion::Query.audits(post).count).to eq(post.audits.count)

    expect(
      CompositeIdentityPostAudit.auditable_finder(
        {auditable_tenant_id: 7, auditable_external_id: "post-7"},
        "CompositeIdentityPost",
        %w[auditable_tenant_id auditable_external_id]
      ).count
    ).to eq(post.audits.count)
    expect(
      CompositeIdentityPostAudit.auditable_finder(
        [7, "post-7"],
        "CompositeIdentityPost",
        %w[auditable_tenant_id auditable_external_id]
      ).count
    ).to eq(post.audits.count)
  ensure
    Object.send(:remove_const, "CompositeIdentityPost") if Object.const_defined?("CompositeIdentityPost")
    Object.send(:remove_const, "CompositeIdentityPostAudit") if Object.const_defined?("CompositeIdentityPostAudit")
    Object.send(:remove_const, "CompositeIdentityPostTranslation") if Object.const_defined?("CompositeIdentityPostTranslation")
    Object.send(:remove_const, "CompositeIdentityPostRevision") if Object.const_defined?("CompositeIdentityPostRevision")
    conn.drop_table(:composite_identity_post_audits, if_exists: true) if conn.data_source_exists?(:composite_identity_post_audits)
    conn.drop_table(:composite_identity_post_translations, if_exists: true) if conn.data_source_exists?(:composite_identity_post_translations)
    conn.drop_table(:composite_identity_post_revisions, if_exists: true) if conn.data_source_exists?(:composite_identity_post_revisions)
    conn.drop_table(:composite_identity_posts, if_exists: true) if conn.data_source_exists?(:composite_identity_posts)
  end
end
