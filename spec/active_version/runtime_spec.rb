require "spec_helper"

RSpec.describe ActiveVersion::Runtime do
  let(:valid_adapter) do
    Class.new do
      def base_connection = nil
      def connection_for(_model_class, _version_type) = nil
    end.new
  end

  after do
    described_class.reset_adapter!
  end

  it "defaults to ActiveRecord adapter when ActiveRecord is loaded" do
    expect(described_class.adapter).to be_a(described_class::ActiveRecordAdapter)
  end

  it "allows overriding the runtime adapter" do
    described_class.adapter = valid_adapter

    expect(described_class.adapter).to eq(valid_adapter)
  end

  it "restores default adapter after reset" do
    described_class.adapter = valid_adapter

    described_class.reset_adapter!

    expect(described_class.adapter).to be_a(described_class::ActiveRecordAdapter)
  end

  it "raises for invalid runtime adapter objects" do
    invalid_adapter = Object.new

    expect do
      described_class.adapter = invalid_adapter
    end.to raise_error(ActiveVersion::ConfigurationError, /must respond to/)
  end

  it "exposes ActiveRecord connection errors when available" do
    errors = described_class.active_record_connection_errors

    expect(errors).to include(ActiveRecord::ConnectionNotEstablished)
    expect(errors).to include(ActiveRecord::NoDatabaseError)
    expect(errors).to include(ActiveRecord::StatementInvalid)
    if defined?(ActiveRecord::ConnectionNotDefined)
      expect(errors).to include(ActiveRecord::ConnectionNotDefined)
    end
  end

  it "reports PostgreSQL capabilities through default runtime adapter" do
    connection = instance_double("Connection", adapter_name: "PostgreSQL")

    expect(described_class.supports_transactional_context?(connection)).to eq(true)
    expect(described_class.supports_current_transaction_id?(connection)).to eq(true)
    expect(described_class.supports_partition_catalog_checks?(connection)).to eq(true)
  end

  it "exposes required adapter methods list" do
    expect(described_class.required_adapter_methods).to eq(%i[base_connection connection_for])
  end

  it "reports adapter contract validity" do
    valid_adapter = Class.new do
      def base_connection = nil
      def connection_for(_model_class, _version_type) = nil
    end.new

    expect(described_class.valid_adapter?(valid_adapter)).to eq(true)
    expect(described_class.valid_adapter?(Object.new)).to eq(false)
  end

  it "supports capability checks via optional adapter methods" do
    adapter = Class.new do
      def base_connection = nil
      def connection_for(_model_class, _version_type) = nil
      def supports_transactional_context?(_connection) = true
      def supports_current_transaction_id?(_connection) = true
      def supports_partition_catalog_checks?(_connection) = true
    end.new
    described_class.adapter = adapter
    connection = instance_double("Connection", adapter_name: "SQLite")

    expect(described_class.supports_transactional_context?(connection)).to eq(true)
    expect(described_class.supports_current_transaction_id?(connection)).to eq(true)
    expect(described_class.supports_partition_catalog_checks?(connection)).to eq(true)
  end

  it "falls back to adapter_name detection when capability methods are absent" do
    adapter = Class.new do
      def base_connection = nil
      def connection_for(_model_class, _version_type) = nil
    end.new
    described_class.adapter = adapter
    pg_connection = instance_double("Connection", adapter_name: "PostgreSQL")
    sqlite_connection = instance_double("Connection", adapter_name: "SQLite")

    expect(described_class.supports_transactional_context?(pg_connection)).to eq(true)
    expect(described_class.supports_current_transaction_id?(pg_connection)).to eq(true)
    expect(described_class.supports_partition_catalog_checks?(pg_connection)).to eq(true)

    expect(described_class.supports_transactional_context?(sqlite_connection)).to eq(false)
    expect(described_class.supports_current_transaction_id?(sqlite_connection)).to eq(false)
    expect(described_class.supports_partition_catalog_checks?(sqlite_connection)).to eq(false)
  end

  it "raises clear error when NullAdapter cannot resolve connection" do
    model_class = Class.new do
      def self.name = "NonArModel"
    end

    expect do
      described_class::NullAdapter.new.connection_for(model_class, :audits)
    end.to raise_error(ActiveVersion::ConfigurationError, /Configure ActiveVersion\.runtime_adapter/)
  end
end
