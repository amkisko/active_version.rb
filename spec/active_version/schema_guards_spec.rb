require "spec_helper"

RSpec.describe ActiveVersion::SchemaGuards do
  describe ".validate_partitioned_keys!" do
    let(:record_class) { class_double("DummyRecord", name: "DummyRecord", table_name: "dummy_records") }
    let(:connection) { instance_double("Connection", adapter_name: "PostgreSQL") }
    let(:runtime_adapter) { instance_double("RuntimeAdapter") }

    before do
      ActiveVersion.config.partition_schema_guards_enabled = true
      described_class.clear_cache!
      allow(runtime_adapter).to receive(:connection_for).with(record_class, :revisions).and_return(connection)
      allow(runtime_adapter).to receive(:supports_partition_catalog_checks?).with(connection).and_return(true)
      allow(ActiveVersion::Runtime).to receive(:adapter).and_return(runtime_adapter)
      allow(connection).to receive(:data_source_exists?).with("dummy_records").and_return(true)
      allow(described_class).to receive(:partitioned_table?).and_return(true)
      allow(described_class).to receive(:partition_key_columns).and_return(["partition_key"])
      allow(described_class).to receive(:expected_unique_columns).and_return(["source_id", "version"])
    end

    after do
      ActiveVersion.config.partition_schema_guards_enabled = false
      described_class.clear_cache!
    end

    it "returns nil when partition schema guards are disabled" do
      ActiveVersion.config.partition_schema_guards_enabled = false

      expect(described_class.validate_partitioned_keys!(record_class, :revisions)).to be_nil
      expect(runtime_adapter).not_to have_received(:connection_for)
    end

    it "returns nil when model has no data source" do
      allow(connection).to receive(:data_source_exists?).with("dummy_records").and_return(false)

      expect(described_class.validate_partitioned_keys!(record_class, :revisions)).to be_nil
    end

    it "raises when partitioned table has no primary key" do
      allow(described_class).to receive(:partition_primary_key_columns).and_return([])

      expect {
        described_class.validate_partitioned_keys!(record_class, :revisions)
      }.to raise_error(ActiveVersion::ConfigurationError, /has no primary key/)
    end

    it "raises when primary key does not include partition key" do
      allow(described_class).to receive(:partition_primary_key_columns).and_return(["id"])

      expect {
        described_class.validate_partitioned_keys!(record_class, :revisions)
      }.to raise_error(ActiveVersion::ConfigurationError, /must be composite and include partition key columns/)
    end

    it "raises when required unique index is missing" do
      allow(described_class).to receive(:partition_primary_key_columns).and_return(["id", "partition_key"])
      allow(connection).to receive(:indexes).with("dummy_records").and_return([])

      expect {
        described_class.validate_partitioned_keys!(record_class, :revisions)
      }.to raise_error(ActiveVersion::ConfigurationError, /Missing unique index/)
    end

    it "passes when unique index includes logical and partition columns" do
      allow(described_class).to receive(:partition_primary_key_columns).and_return(["id", "partition_key"])

      good_index = instance_double("Index", unique: true, columns: %w[source_id version partition_key])
      allow(connection).to receive(:indexes).with("dummy_records").and_return([good_index])

      expect(described_class.validate_partitioned_keys!(record_class, :revisions)).to be_nil
    end

    it "memoizes successful validations to avoid repeated metadata queries" do
      allow(described_class).to receive(:partition_primary_key_columns).and_return(["id", "partition_key"])
      allow(connection).to receive(:indexes).with("dummy_records").and_return(
        [instance_double("Index", unique: true, columns: %w[source_id version partition_key])]
      )

      expect(described_class).to receive(:partitioned_table?).once.and_return(true)

      described_class.validate_partitioned_keys!(record_class, :revisions)
      described_class.validate_partitioned_keys!(record_class, :revisions)
    end

    it "is best-effort when connection is not defined" do
      allow(runtime_adapter).to receive(:connection_for).with(record_class, :revisions).and_raise(ActiveRecord::ConnectionNotDefined)

      expect(described_class.validate_partitioned_keys!(record_class, :revisions)).to be_nil
    end
  end

  describe ".expected_unique_columns" do
    let(:record_class) { class_double("VersionRecord") }
    let(:source_class) { class_double("SourceRecord") }
    let(:column_mapper) { instance_double("ColumnMapper") }

    before do
      allow(record_class).to receive(:source_class).and_return(source_class)
      allow(record_class).to receive(:source_foreign_key).and_return("source_id")
      allow(ActiveVersion).to receive(:column_mapper).and_return(column_mapper)
    end

    it "builds expected columns for audits" do
      allow(column_mapper).to receive(:column_for).with(source_class, :audits, :auditable).and_return(:auditable)
      allow(column_mapper).to receive(:column_for).with(source_class, :audits, :version).and_return(:version)

      expect(described_class.expected_unique_columns(record_class, :audits))
        .to eq(%w[auditable_type auditable_id version])
    end

    it "builds expected columns for revisions and translations" do
      allow(column_mapper).to receive(:column_for).with(source_class, :revisions, :version).and_return(:version)
      allow(column_mapper).to receive(:column_for).with(source_class, :translations, :locale).and_return(:locale)

      expect(described_class.expected_unique_columns(record_class, :revisions)).to eq(%w[source_id version])
      expect(described_class.expected_unique_columns(record_class, :translations)).to eq(%w[source_id locale])
    end
  end
end
