require "spec_helper"

RSpec.describe "ActiveVersion custom runtime adapter contract" do
  class FakeConnection
    attr_reader :executed_sql

    def initialize(adapter_name: "FakeDB", open_transactions: 0)
      @adapter_name = adapter_name
      @open_transactions = open_transactions
      @executed_sql = []
    end

    attr_reader :adapter_name

    attr_reader :open_transactions

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

  before do
    ActiveVersion.clear_context!
    ActiveVersion.reset_runtime_adapter!
  end

  after do
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

  it "queries current transaction id through custom adapter base connection" do
    connection = FakeConnection.new(adapter_name: "PostgreSQL")
    adapter = FakeRuntimeAdapter.new(base_connection: connection)
    ActiveVersion.runtime_adapter = adapter

    expect(current_transaction_id).to eq("fake-tx-id")
    expect(connection.executed_sql).to include("SELECT pg_current_xact_id()")
  end
end
