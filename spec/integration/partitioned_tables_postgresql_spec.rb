require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion on partitioned tables (PostgreSQL)", type: :integration do
  AUDITS_PARENT = "av_partitioned_post_audits".freeze
  AUDITS_PARTITION = "av_partitioned_post_audits_partitioned_post".freeze
  AUDITS_DEFAULT = "av_partitioned_post_audits_default".freeze

  REVISIONS_PARENT = "av_partitioned_post_revisions".freeze
  REVISIONS_PARTITION = "av_partitioned_post_revisions_100000_200000".freeze
  REVISIONS_DEFAULT = "av_partitioned_post_revisions_default".freeze

  TRANSLATIONS_PARENT = "av_partitioned_post_translations".freeze
  TRANSLATIONS_PARTITION = "av_partitioned_post_translations_en".freeze
  TRANSLATIONS_DEFAULT = "av_partitioned_post_translations_default".freeze

  before(:all) do
    DatabaseHelper.setup
    skip "Partitioned table integration tests require PostgreSQL" unless postgresql?
    setup_partitioned_tables!
    define_partitioned_models!
  end

  after(:all) do
    if postgresql?
      cleanup_partitioned_data!
      drop_partitioned_tables!
      remove_partitioned_models!
    end
    DatabaseHelper.teardown
  end

  before do
    cleanup_partitioned_data!
    cleanup_test_data
    reset_active_version_context
    ActiveVersion.clear_context!
  end

  it "writes audits to list partitions using auditable_type and falls back to DEFAULT" do
    post = PartitionedPost.create!(title: "audit-target")
    post.update!(title: "audit-target-2")

    partitioned_audit = PartitionedPostAudit.find_by!(
      auditable_type: "PartitionedPost",
      auditable_id: post.id,
      version: 1
    )
    expect(
      partition_name_for_where(
        AUDITS_PARENT,
        "auditable_type = 'PartitionedPost' AND auditable_id = #{post.id} AND version = 1"
      )
    ).to eq(AUDITS_PARTITION)

    alt = PartitionedPostAlt.create!(title: "audit-default")
    alt_audit = PartitionedPostAudit.find_by!(
      auditable_type: "PartitionedPostAlt",
      auditable_id: alt.id,
      version: 1
    )
    expect(
      partition_name_for_where(
        AUDITS_PARENT,
        "auditable_type = 'PartitionedPostAlt' AND auditable_id = #{alt.id} AND version = 1"
      )
    ).to eq(AUDITS_DEFAULT)
  end

  it "writes revisions to range partitions with source FK in the key and falls back to DEFAULT" do
    in_range = PartitionedPost.create!(id: 150_000, title: "v1")
    in_range.update!(title: "v2")
    explicit_revision = PartitionedPostRevision.find_by!(partitioned_post_id: in_range.id, version: 1)
    expect(
      partition_name_for_where(
        REVISIONS_PARENT,
        "partitioned_post_id = #{explicit_revision.partitioned_post_id} AND version = #{explicit_revision.version}"
      )
    ).to eq(REVISIONS_PARTITION)

    default_row = PartitionedPost.create!(title: "default-v1")
    default_row.update!(title: "default-v2")
    default_revision = PartitionedPostRevision.find_by!(partitioned_post_id: default_row.id, version: 1)
    expect(
      partition_name_for_where(
        REVISIONS_PARENT,
        "partitioned_post_id = #{default_revision.partitioned_post_id} AND version = #{default_revision.version}"
      )
    ).to eq(REVISIONS_DEFAULT)
  end

  it "supports param_to_id/id_to_param for composite ids in find/where flows" do
    post = PartitionedPost.create!(id: 150_500, title: "v1")
    post.update!(title: "v2")
    post.update!(title: "v3")

    rev1 = PartitionedPostRevision.find_by!(partitioned_post_id: post.id, version: 1)
    rev2 = PartitionedPostRevision.find_by!(partitioned_post_id: post.id, version: 2)

    single_encoded = PartitionedPostRevision.id_to_param([rev1.partitioned_post_id, rev1.version])
    single_id = PartitionedPostRevision.param_to_id(single_encoded)
    expect(PartitionedPostRevision.find(single_id).version).to eq(1)

    encoded_ids = [
      PartitionedPostRevision.id_to_param([rev1.partitioned_post_id, rev1.version]),
      PartitionedPostRevision.id_to_param([rev2.partitioned_post_id, rev2.version])
    ]
    ids = encoded_ids.map { |raw| PartitionedPostRevision.param_to_id(raw) }
    expect(ids).to all(be_an(Array))

    records = PartitionedPostRevision.where(PartitionedPostRevision.primary_key => ids)
    expect(records.count).to eq(2)
  end

  it "writes translations to locale partitions and uses DEFAULT for unmapped locales" do
    post = PartitionedPost.create!(title: "Hello", body: "World")
    en_translation = PartitionedPostTranslation.find_by!(partitioned_post_id: post.id, locale: "en")
    expect(
      partition_name_for_where(
        TRANSLATIONS_PARENT,
        "partitioned_post_id = #{en_translation.partitioned_post_id} AND locale = 'en'"
      )
    ).to eq(TRANSLATIONS_PARTITION)

    post.translations.create!(locale: "fi", title: "Hei", body: "Maailma")
    fi_translation = PartitionedPostTranslation.find_by!(partitioned_post_id: post.id, locale: "fi")
    expect(
      partition_name_for_where(
        TRANSLATIONS_PARENT,
        "partitioned_post_id = #{fi_translation.partitioned_post_id} AND locale = 'fi'"
      )
    ).to eq(TRANSLATIONS_DEFAULT)
  end

  def postgresql?
    connection.adapter_name == "PostgreSQL"
  end

  def setup_partitioned_tables!
    drop_partitioned_tables!

    connection.execute(<<~SQL)
      CREATE TABLE #{AUDITS_PARENT} (
        id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
        auditable_type text NOT NULL,
        auditable_id bigint NOT NULL,
        action text NOT NULL,
        audited_changes text,
        version integer NOT NULL,
        user_type text,
        user_id bigint,
        comment text,
        audited_context text,
        remote_address text,
        request_uuid text,
        created_at timestamp,
        updated_at timestamp,
        PRIMARY KEY (auditable_type, id)
      ) PARTITION BY LIST (auditable_type);
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{AUDITS_PARTITION}
      PARTITION OF #{AUDITS_PARENT}
      FOR VALUES IN ('PartitionedPost');
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{AUDITS_DEFAULT}
      PARTITION OF #{AUDITS_PARENT}
      DEFAULT;
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{REVISIONS_PARENT} (
        partitioned_post_id bigint NOT NULL,
        version integer NOT NULL,
        title text,
        body text,
        status text,
        created_at timestamp,
        updated_at timestamp,
        PRIMARY KEY (partitioned_post_id, version)
      ) PARTITION BY RANGE (partitioned_post_id);
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{REVISIONS_PARTITION}
      PARTITION OF #{REVISIONS_PARENT}
      FOR VALUES FROM (100000) TO (200000);
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{REVISIONS_DEFAULT}
      PARTITION OF #{REVISIONS_PARENT}
      DEFAULT;
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{TRANSLATIONS_PARENT} (
        partitioned_post_id bigint NOT NULL,
        locale text NOT NULL,
        title text,
        body text,
        created_at timestamp,
        updated_at timestamp,
        PRIMARY KEY (locale, partitioned_post_id)
      ) PARTITION BY LIST (locale);
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{TRANSLATIONS_PARTITION}
      PARTITION OF #{TRANSLATIONS_PARENT}
      FOR VALUES IN ('en');
    SQL

    connection.execute(<<~SQL)
      CREATE TABLE #{TRANSLATIONS_DEFAULT}
      PARTITION OF #{TRANSLATIONS_PARENT}
      DEFAULT;
    SQL
  end

  def drop_partitioned_tables!
    connection.execute("DROP TABLE IF EXISTS #{AUDITS_PARENT} CASCADE")
    connection.execute("DROP TABLE IF EXISTS #{REVISIONS_PARENT} CASCADE")
    connection.execute("DROP TABLE IF EXISTS #{TRANSLATIONS_PARENT} CASCADE")
  end

  def cleanup_partitioned_data!
    connection.execute("DELETE FROM #{AUDITS_PARENT}") if table_exists?(AUDITS_PARENT)
    connection.execute("DELETE FROM #{REVISIONS_PARENT}") if table_exists?(REVISIONS_PARENT)
    connection.execute("DELETE FROM #{TRANSLATIONS_PARENT}") if table_exists?(TRANSLATIONS_PARENT)
  end

  def table_exists?(name)
    connection.data_source_exists?(name)
  end

  def define_partitioned_models!
    remove_partitioned_models!

    Object.const_set("PartitionedPostTranslation", Class.new(ApplicationRecord) do
      self.table_name = TRANSLATIONS_PARENT
      self.primary_key = [:locale, :partitioned_post_id]
      include ActiveVersion::Translations::TranslationRecord
    end)

    Object.const_set("PartitionedPostRevision", Class.new(ApplicationRecord) do
      self.table_name = REVISIONS_PARENT
      self.primary_key = [:partitioned_post_id, :version]
      include ActiveVersion::Revisions::RevisionRecord
    end)

    Object.const_set("PartitionedPostAudit", Class.new(ApplicationRecord) do
      self.table_name = AUDITS_PARENT
      include ActiveVersion::Audits::AuditRecord
    end)

    Object.const_set("PartitionedPost", Class.new(ApplicationRecord) do
      self.table_name = "posts"

      include ActiveVersion::Translations::HasTranslations
      include ActiveVersion::Revisions::HasRevisions
      include ActiveVersion::Audits::HasAudits
    end)

    Object.const_set("PartitionedPostAlt", Class.new(ApplicationRecord) do
      self.table_name = "posts"

      include ActiveVersion::Audits::HasAudits
    end)

    PartitionedPost.has_translations
    PartitionedPost.has_revisions(as: PartitionedPostRevision)
    PartitionedPost.has_audits(as: PartitionedPostAudit)
    PartitionedPostAlt.has_audits(as: PartitionedPostAudit)
    PartitionedPost.setup_translation_associations if PartitionedPost.respond_to?(:setup_translation_associations)

    PartitionedPostTranslation.setup_associations if PartitionedPostTranslation.respond_to?(:setup_associations)
    PartitionedPostRevision.setup_associations if PartitionedPostRevision.respond_to?(:setup_associations)
    PartitionedPostAudit.setup_associations if PartitionedPostAudit.respond_to?(:setup_associations)
  end

  def remove_partitioned_models!
    [:PartitionedPostAlt, :PartitionedPost, :PartitionedPostAudit, :PartitionedPostRevision, :PartitionedPostTranslation].each do |const_name|
      Object.send(:remove_const, const_name) if Object.const_defined?(const_name)
    end
  end

  def partition_name_for_where(parent_table, where_sql)
    connection.select_value(
      "SELECT tableoid::regclass::text FROM #{parent_table} WHERE #{where_sql} LIMIT 1"
    )
  end

  def connection
    ActiveRecord::Base.connection
  end
end
