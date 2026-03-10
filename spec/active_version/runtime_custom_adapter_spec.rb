require "spec_helper"

RSpec.describe "ActiveVersion custom runtime adapter contract" do
  class FakeConnection
    attr_reader :executed_sql

    def initialize(adapter_name: "FakeDB", open_transactions: 0)
      @adapter_name = adapter_name
      @open_transactions = open_transactions
      @executed_sql = []
    end

    def adapter_name
      @adapter_name
    end

    def open_transactions
      @open_transactions
    end

    def quote(value)
      "'#{value}'"
    end

    def execute(sql)
      @executed_sql << sql
      [["fake-tx-id"]]
    end
  end

  class FakeRuntimeAdapter
    attr_reader :base_connection_calls, :connection_for_calls

    def initialize(base_connection:, routed_connection: nil)
      @base_connection = base_connection
      @routed_connection = routed_connection || base_connection
      @base_connection_calls = 0
      @connection_for_calls = []
    end

    def base_connection
      @base_connection_calls += 1
      @base_connection
    end

    def connection_for(model_class, version_type)
      @connection_for_calls << [model_class, version_type]
      @routed_connection
    end

    def supports_transactional_context?(connection)
      connection.adapter_name == "PostgreSQL"
    end

    def supports_current_transaction_id?(connection)
      connection.adapter_name == "PostgreSQL"
    end

    def supports_partition_catalog_checks?(connection)
      connection.adapter_name == "PostgreSQL"
    end
  end

  let(:record_class) { class_double("RuntimeContractRecord", table_name: "runtime_contract_records", name: "RuntimeContractRecord") }

  before do
    ActiveVersion.clear_context!
    ActiveVersion.reset_runtime_adapter!
    ActiveVersion.config.partition_schema_guards_enabled = false
    ActiveVersion::SchemaGuards.clear_cache!
  end

  after do
    ActiveVersion.config.partition_schema_guards_enabled = false
    ActiveVersion::SchemaGuards.clear_cache!
    ActiveVersion.reset_runtime_adapter!
  end

  it "supports transactional context using custom adapter base connection" do
    connection = FakeConnection.new(adapter_name: "PostgreSQL", open_transactions: 1)
    adapter = FakeRuntimeAdapter.new(base_connection: connection)
    ActiveVersion.runtime_adapter = adapter

    ActiveVersion.with_context(ip: "127.0.0.1") do
      expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")
    end

    expect(connection.executed_sql.any? { |sql| sql.include?("SET LOCAL active_version.context") }).to eq(true)
    expect(adapter.base_connection_calls).to be >= 1
  end

  it "routes query current_transaction through custom adapter base connection" do
    connection = FakeConnection.new(adapter_name: "PostgreSQL")
    adapter = FakeRuntimeAdapter.new(base_connection: connection)
    ActiveVersion.runtime_adapter = adapter

    expect(ActiveVersion::Query.current_transaction).to eq("fake-tx-id")
    expect(connection.executed_sql).to include("SELECT pg_current_xact_id()")
  end

  it "routes schema guards through custom adapter connection_for" do
    routed_connection = instance_double("RoutedConnection", adapter_name: "PostgreSQL")
    adapter = FakeRuntimeAdapter.new(base_connection: FakeConnection.new, routed_connection: routed_connection)
    ActiveVersion.runtime_adapter = adapter
    ActiveVersion.config.partition_schema_guards_enabled = true

    allow(routed_connection).to receive(:data_source_exists?).with("runtime_contract_records").and_return(false)

    expect(ActiveVersion::SchemaGuards.validate_partitioned_keys!(record_class, :audits)).to be_nil
    expect(adapter.connection_for_calls).to include([record_class, :audits])
  end
end
