require "spec_helper"
require "active_record"

RSpec.describe "ActiveVersion Migrators::Base Integration", type: :integration do
  let(:connection) { ActiveRecord::Base.connection }

  before(:all) do
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )
  end

  after do
    # Clean up tables created during tests (this also drops indexes)
    connection.drop_table(:test_audits) if connection.table_exists?(:test_audits)
    connection.drop_table(:test_revisions) if connection.table_exists?(:test_revisions)
    connection.drop_table(:test_translations) if connection.table_exists?(:test_translations)
  rescue => e
    # Ignore errors during cleanup
    puts "Cleanup warning: #{e.message}" if ENV["DEBUG"]
  end

  describe "create_audit_table" do
    it "creates audit table with required columns and minimal indexes" do
      ActiveVersion::Migrators::Base.create_audit_table(:test_audits)

      # Verify table exists
      expect(connection.table_exists?(:test_audits)).to be true

      # Verify columns
      columns = connection.columns(:test_audits).map(&:name)
      expect(columns).to include("id")
      expect(columns).to include("auditable_id")
      expect(columns).to include("auditable_type")
      expect(columns).to include("action")
      expect(columns).to include("version")
      expect(columns).to include("user_id")
      expect(columns).to include("user_type")
      expect(columns).to include("associated_id")
      expect(columns).to include("associated_type")
      expect(columns).to include("comment")
      expect(columns).to include("audited_context")
      expect(columns).to include("remote_address")
      expect(columns).to include("request_uuid")
      expect(columns).to include("audited_changes")
      expect(columns).to include("created_at")
      expect(columns).to include("updated_at")

      # Verify indexes
      indexes = connection.indexes(:test_audits).map(&:name)
      expect(indexes).to include("index_test_audits_on_auditable_and_version")
      expect(indexes).not_to include("index_test_audits_on_auditable")
      expect(indexes).not_to include("index_test_audits_on_action")
      expect(indexes).not_to include("index_test_audits_on_created_at")
    end

    it "creates audit table with custom options" do
      ActiveVersion::Migrators::Base.create_audit_table(:test_audits, force: true, id: :uuid)

      expect(connection.table_exists?(:test_audits)).to be true
      # Verify UUID primary key if supported
      id_column = connection.columns(:test_audits).find { |c| c.name == "id" }
      expect(id_column).to be_present
    end

    it "allows inserting and querying audit records" do
      ActiveVersion::Migrators::Base.create_audit_table(:test_audits)

      # Create a test model class
      test_class = Class.new(ApplicationRecord) do
        self.table_name = "test_audits"
        include ActiveVersion::Audits::AuditRecord
      end

      # Insert a record
      audit = test_class.create!(
        auditable_type: "Post",
        auditable_id: 1,
        action: "create",
        version: 1,
        audited_changes: {"title" => "Hello"}
      )

      expect(audit).to be_persisted
      expect(audit.auditable_type).to eq("Post")
      expect(audit.auditable_id).to eq(1)
      expect(audit.action).to eq("create")
      expect(audit.version).to eq(1)

      # Query by auditable
      found = test_class.where(auditable_type: "Post", auditable_id: 1).first
      expect(found).to eq(audit)
    end

    it "supports yaml_column storage payload columns" do
      ActiveVersion::Migrators::Base.create_audit_table(:test_audits, storage: :yaml_column)

      columns = connection.columns(:test_audits).index_by(&:name)
      expect(columns.fetch("audited_changes").type).to eq(:text)
      expect(columns.fetch("audited_context").type).to eq(:text)
    end

    it "supports mirror_columns storage with explicit mirrored columns" do
      ActiveVersion::Migrators::Base.create_audit_table(
        :test_audits,
        storage: :mirror_columns,
        mirror_columns: {title: :string, published: :boolean}
      )

      columns = connection.columns(:test_audits).map(&:name)
      expect(columns).to include("title", "published")
      expect(columns).not_to include("audited_changes")
      expect(columns).not_to include("audited_context")
    end

    it "supports overriding payload column names" do
      ActiveVersion::Migrators::Base.create_audit_table(
        :test_audits,
        changes_column: :audit_payload,
        context_column: :audit_meta
      )

      columns = connection.columns(:test_audits).map(&:name)
      expect(columns).to include("audit_payload", "audit_meta")
      expect(columns).not_to include("audited_changes")
      expect(columns).not_to include("audited_context")
    end

    it "raises on unknown storage mode" do
      expect {
        ActiveVersion::Migrators::Base.create_audit_table(:test_audits, storage: :xml)
      }.to raise_error(ActiveVersion::ConfigurationError, /Unknown audit storage/)
    end
  end

  describe "create_revision_table" do
    it "creates revision table with required columns and minimal indexes" do
      ActiveVersion::Migrators::Base.create_revision_table(:test_revisions)

      # Verify table exists
      expect(connection.table_exists?(:test_revisions)).to be true

      # Verify columns
      columns = connection.columns(:test_revisions).map(&:name)
      expect(columns).to include("id")
      expect(columns).to include("source_id")
      expect(columns).to include("source_type")
      expect(columns).to include("version")
      expect(columns).to include("comment")
      expect(columns).to include("created_at")
      expect(columns).to include("updated_at")

      # Verify indexes
      indexes = connection.indexes(:test_revisions).map(&:name)
      expect(indexes).to include("index_test_revisions_on_source_and_version")
      expect(indexes).not_to include("index_test_revisions_on_source")
    end

    it "allows inserting and querying revision records" do
      ActiveVersion::Migrators::Base.create_revision_table(:test_revisions)

      test_class = Class.new(ApplicationRecord) do
        self.table_name = "test_revisions"
      end

      revision = test_class.create!(
        source_type: "Post",
        source_id: 1,
        version: 1
      )

      expect(revision).to be_persisted
      expect(revision.source_type).to eq("Post")
      expect(revision.source_id).to eq(1)
      expect(revision.version).to eq(1)

      # Query by source
      found = test_class.where(source_type: "Post", source_id: 1).first
      expect(found).to eq(revision)
    end
  end

  describe "create_translation_table" do
    it "creates translation table with all required columns and indexes" do
      ActiveVersion::Migrators::Base.create_translation_table(:test_translations)

      # Verify table exists
      expect(connection.table_exists?(:test_translations)).to be true

      # Verify columns
      columns = connection.columns(:test_translations).map(&:name)
      expect(columns).to include("id")
      expect(columns).to include("source_id")
      expect(columns).to include("source_type")
      expect(columns).to include("locale")
      expect(columns).to include("created_at")
      expect(columns).to include("updated_at")

      # Verify indexes
      indexes = connection.indexes(:test_translations).map(&:name)
      expect(indexes).to include("index_test_translations_on_source_and_locale")
    end

    it "allows inserting and querying translation records" do
      ActiveVersion::Migrators::Base.create_translation_table(:test_translations)

      test_class = Class.new(ApplicationRecord) do
        self.table_name = "test_translations"
      end

      translation = test_class.create!(
        source_type: "Post",
        source_id: 1,
        locale: "en"
      )

      expect(translation).to be_persisted
      expect(translation.source_type).to eq("Post")
      expect(translation.source_id).to eq(1)
      expect(translation.locale).to eq("en")

      # Query by source and locale
      found = test_class.where(source_type: "Post", source_id: 1, locale: "en").first
      expect(found).to eq(translation)
    end
  end

  describe "base migration contract helpers" do
    it "raises NotImplementedError for abstract migrate" do
      expect do
        ActiveVersion::Migrators::Base.migrate(Post)
      end.to raise_error(NotImplementedError, /Subclasses must implement migrate/)
    end

    it "normalizes mirror_columns from Array to :text column map" do
      expect(
        ActiveVersion::Migrators::Base.send(:normalize_mirror_columns, [:title, :body])
      ).to eq({title: :text, body: :text})
    end

    it "raises when mirror_columns is not a Hash, Array, or nil" do
      expect do
        ActiveVersion::Migrators::Base.send(:normalize_mirror_columns, "oops")
      end.to raise_error(ArgumentError, /mirror_columns must be/)
    end

    it "chooses payload column type for json_column storage" do
      expect(
        ActiveVersion::Migrators::Base.send(:payload_column_type_for, :json_column)
      ).to be_a(Symbol)
    end

    it "returns nil from current_connection when ActiveRecord connection raises" do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished)
      expect(ActiveVersion::Migrators::Base.send(:current_connection)).to be_nil
    end

    it "exposes protected helper methods for subclasses" do
      model_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
      end

      source_relation = ActiveVersion::Migrators::Base.send(:source_records, model_class)
      expect(source_relation).to eq(model_class.all)

      audit_class = class_double("AuditClass")
      revision_class = class_double("RevisionClass")
      translation_class = class_double("TranslationClass")
      allow(audit_class).to receive(:create!).and_return(:audit)
      allow(revision_class).to receive(:create!).and_return(:revision)
      allow(translation_class).to receive(:create!).and_return(:translation)

      expect(
        ActiveVersion::Migrators::Base.send(:create_audit, :record, {action: "create"}, audit_class)
      ).to eq(:audit)
      expect(
        ActiveVersion::Migrators::Base.send(:create_revision, :record, {version: 1}, revision_class)
      ).to eq(:revision)
      expect(
        ActiveVersion::Migrators::Base.send(:create_translation, :record, {locale: "en"}, translation_class)
      ).to eq(:translation)
    end
  end
end
