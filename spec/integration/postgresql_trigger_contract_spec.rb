require "spec_helper"

RSpec.describe ActiveVersion::Database::Triggers::PostgreSQL do
  let(:connection) { ActiveRecord::Base.connection }
  let(:table_name) { "trigger_records" }
  let(:audit_table) { "trigger_audits" }

  before do
    DatabaseHelper.setup
    skip "PostgreSQL required" unless connection.adapter_name.match?(/postgres/i)
    connection.execute("CREATE TABLE #{connection.quote_table_name(table_name)} (id bigint PRIMARY KEY, title text, status text)")
    connection.execute(<<~SQL)
      CREATE TABLE #{connection.quote_table_name(audit_table)} (
        auditable_id bigint, auditable_type text, action text, audited_changes jsonb,
        version integer, audited_context jsonb, created_at timestamp, updated_at timestamp
      )
    SQL
    connection.execute(described_class.generate_audit_trigger_function(table_name, audit_table))
    connection.execute(described_class.generate_audit_trigger(table_name))
  end

  after do
    if connection.adapter_name.match?(/postgres/i)
      connection.execute("DROP TABLE IF EXISTS #{connection.quote_table_name(table_name)} CASCADE")
      connection.execute("DROP TABLE IF EXISTS #{connection.quote_table_name(audit_table)} CASCADE")
      connection.execute(described_class.drop_trigger_function("active_version_audit_#{table_name}"))
    end
  end

  it "records only changed fields as old and new pairs" do
    connection.execute("INSERT INTO trigger_records VALUES (1, 'before', 'draft')")
    connection.execute("UPDATE trigger_records SET title = 'after' WHERE id = 1")

    changes = connection.select_value("SELECT audited_changes FROM trigger_audits WHERE action = 'update'")

    expect(JSON.parse(changes)).to eq("title" => ["before", "after"])
  end

  it "uses an empty context after transaction-local context is reset" do
    connection.transaction do
      connection.execute(%q(SET LOCAL active_version.context = '{"operation":"create"}'))
      connection.execute("INSERT INTO trigger_records VALUES (1, 'before', 'draft')")
    end
    connection.execute("UPDATE trigger_records SET title = 'after' WHERE id = 1")

    context = connection.select_value("SELECT audited_context FROM trigger_audits WHERE action = 'update'")
    expect(JSON.parse(context)).to eq({})
  end

  it "executes revision triggers with explicit payload columns" do
    connection.execute("CREATE TABLE trigger_revisions (trigger_record_id bigint, version integer, title text, status text, created_at timestamp, updated_at timestamp)")
    connection.execute(described_class.generate_revision_trigger_function(
      table_name, "trigger_revisions", foreign_key: "trigger_record_id", columns: %w[id title status]
    ))
    connection.execute(described_class.generate_revision_trigger(table_name))
    connection.execute("INSERT INTO trigger_records VALUES (1, 'before', 'draft')")
    connection.execute("UPDATE trigger_records SET title = 'after' WHERE id = 1")

    expect(connection.select_one("SELECT trigger_record_id, version, title, status FROM trigger_revisions"))
      .to eq("trigger_record_id" => 1, "version" => 1, "title" => "before", "status" => "draft")
  ensure
    connection.execute("DROP TABLE IF EXISTS trigger_revisions")
    connection.execute(described_class.drop_trigger_function("active_version_revision_#{table_name}"))
  end

  it "records create and destroy snapshots with consecutive versions" do
    connection.execute("INSERT INTO trigger_records VALUES (1, 'before', 'draft')")
    connection.execute("DELETE FROM trigger_records WHERE id = 1")

    records = connection.select_all("SELECT auditable_type, action, version, audited_changes FROM trigger_audits ORDER BY version").to_a
    aggregate_failures do
      expect(records.map { |record| record.values_at("auditable_type", "action", "version") })
        .to eq([["TriggerRecord", "create", 1], ["TriggerRecord", "destroy", 2]])
      expect(records.map { |record| JSON.parse(record.fetch("audited_changes")) })
        .to eq(Array.new(2) { {"id" => 1, "title" => "before", "status" => "draft"} })
    end
  end

  it "suppresses create, update, and destroy audits while disabled" do
    connection.transaction do
      connection.execute("SET LOCAL active_version.disabled = 'on'")
      connection.execute("INSERT INTO trigger_records VALUES (1, 'before', 'draft')")
      connection.execute("UPDATE trigger_records SET title = 'after' WHERE id = 1")
      connection.execute("DELETE FROM trigger_records WHERE id = 1")
    end

    expect(connection.select_value("SELECT COUNT(*) FROM trigger_audits")).to eq(0)
  end

  context "with quoted identifiers" do
    let(:table_name) { "trigger Records" }
    let(:audit_table) { "trigger Audits" }

    it "executes inserts and records the quoted source table" do
      connection.execute("INSERT INTO #{connection.quote_table_name(table_name)} VALUES (1, 'quoted', 'draft')")

      expect(connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(audit_table)}")).to eq(1)
    end
  end
end
