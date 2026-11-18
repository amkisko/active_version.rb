require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion jsonb audit payload storage", type: :integration do
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

  it "stores audit payloads as jsonb objects so SQL key operators match Ruby accessors" do
    connection = ActiveRecord::Base.connection
    skip "PostgreSQL required" unless connection.adapter_name.match?(/postgres/i)

    connection.execute(<<~SQL)
      CREATE TABLE jsonb_payload_posts (
        id bigserial PRIMARY KEY,
        title text,
        user_id bigint,
        created_at timestamp,
        updated_at timestamp
      )
    SQL
    connection.execute(<<~SQL)
      CREATE TABLE jsonb_payload_post_audits (
        id bigserial PRIMARY KEY,
        auditable_type text NOT NULL,
        auditable_id bigint NOT NULL,
        action text NOT NULL,
        audited_changes jsonb,
        version integer NOT NULL,
        audited_context jsonb,
        created_at timestamp,
        updated_at timestamp
      )
    SQL

    audit_class = Class.new(ApplicationRecord) do
      include ActiveVersion::Audits::AuditRecord

      self.table_name = "jsonb_payload_post_audits"
      def self.name = "JsonbPayloadPostAudit"
    end
    Object.const_set(:JsonbPayloadPostAudit, audit_class)

    post_class = Class.new(ApplicationRecord) do
      include ActiveVersion::Audits::HasAudits

      self.table_name = "jsonb_payload_posts"
      def self.name = "JsonbPayloadPost"
      has_audits as: JsonbPayloadPostAudit, class_name: "JsonbPayloadPost"
    end
    Object.const_set(:JsonbPayloadPost, post_class)
    audit_class.setup_associations if audit_class.respond_to?(:setup_associations)

    expect(audit_class.serialize_audit_payload({"user_id" => [1, nil]}, column_name: :audited_changes))
      .to eq({"user_id" => [1, nil]})

    connection.transaction(requires_new: true) do
      post = JsonbPayloadPost.create!(title: "Doctor", user_id: 1)
      post.update!(user_id: nil)
      audit = JsonbPayloadPostAudit.where(auditable_id: post.id, action: "update").order(:version).last

      typeof = connection.select_value(
        "SELECT jsonb_typeof(audited_changes) FROM jsonb_payload_post_audits WHERE id = #{audit.id}"
      )
      key_present = connection.select_value(
        "SELECT audited_changes ? 'user_id' FROM jsonb_payload_post_audits WHERE id = #{audit.id}"
      )

      expect(typeof).to eq("object")
      expect(key_present).to eq(true)
      expect(audit.audited_changes.key?("user_id")).to eq(true)

      raise ActiveRecord::Rollback
    end
  ensure
    Object.send(:remove_const, :JsonbPayloadPost) if Object.const_defined?(:JsonbPayloadPost)
    Object.send(:remove_const, :JsonbPayloadPostAudit) if Object.const_defined?(:JsonbPayloadPostAudit)
    if connection&.adapter_name&.match?(/postgres/i)
      connection.execute("DROP TABLE IF EXISTS jsonb_payload_post_audits")
      connection.execute("DROP TABLE IF EXISTS jsonb_payload_posts")
    end
  end

  it "still decodes legacy string-shaped jsonb payloads on read" do
    connection = ActiveRecord::Base.connection
    skip "PostgreSQL required" unless connection.adapter_name.match?(/postgres/i)

    connection.execute(<<~SQL)
      CREATE TABLE jsonb_legacy_audits (
        id bigserial PRIMARY KEY,
        auditable_type text NOT NULL,
        auditable_id bigint NOT NULL,
        action text NOT NULL,
        audited_changes jsonb,
        version integer NOT NULL,
        created_at timestamp,
        updated_at timestamp
      )
    SQL

    audit_class = Class.new(ApplicationRecord) do
      include ActiveVersion::Audits::AuditRecord

      self.table_name = "jsonb_legacy_audits"
      def self.name = "JsonbLegacyAudit"
      configure_audit do
        storage :json_column
      end
    end
    Object.const_set(:JsonbLegacyAudit, audit_class)
    audit_class.setup_associations if audit_class.respond_to?(:setup_associations)

    encoded = ActiveVersion.json_encode({"user_id" => [1, nil]})
    # Plant a string scalar the way double-encoded writes used to land.
    connection.execute(<<~SQL)
      INSERT INTO jsonb_legacy_audits
        (auditable_type, auditable_id, action, audited_changes, version, created_at, updated_at)
      VALUES
        ('Legacy', 1, 'update', to_jsonb(#{connection.quote(encoded)}::text), 1, NOW(), NOW())
    SQL

    audit = JsonbLegacyAudit.first
    expect(connection.select_value("SELECT jsonb_typeof(audited_changes) FROM jsonb_legacy_audits WHERE id = #{audit.id}"))
      .to eq("string")
    expect(audit.audited_changes).to eq("user_id" => [1, nil])
  ensure
    Object.send(:remove_const, :JsonbLegacyAudit) if Object.const_defined?(:JsonbLegacyAudit)
    connection.execute("DROP TABLE IF EXISTS jsonb_legacy_audits") if connection&.adapter_name&.match?(/postgres/i)
  end
end
