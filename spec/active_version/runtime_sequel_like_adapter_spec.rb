require "spec_helper"

RSpec.describe "ActiveVersion Sequel-like runtime adapter prototype" do
  class SequelLikeDatabase
    attr_reader :sql_log

    def initialize(adapter_name: "PostgreSQL")
      @adapter_name = adapter_name
      @sql_log = []
    end

    def database_type
      @adapter_name.downcase.to_sym
    end

    def run(sql)
      @sql_log << sql
      [["sequel-like-tx-id"]]
    end
  end

  class SequelLikeConnection
    def initialize(db:, open_transactions: 0)
      @db = db
      @open_transactions = open_transactions
    end

    def adapter_name
      @db.database_type.to_s.capitalize
    end

    attr_reader :open_transactions

    def quote(value)
      "'#{value}'"
    end

    def execute(sql)
      @db.run(sql)
    end
  end

  class SequelLikeRuntimeAdapter
    def initialize(base_db:, routed_db: nil)
      @base_db = base_db
      @routed_db = routed_db || base_db
    end

    def base_connection
      SequelLikeConnection.new(db: @base_db, open_transactions: 1)
    end

    def connection_for(_model_class, _version_type)
      SequelLikeConnection.new(db: @routed_db)
    end

    def supports_transactional_context?(connection)
      connection.adapter_name.casecmp("postgresql").zero?
    end

    def supports_current_transaction_id?(connection)
      connection.adapter_name.casecmp("postgresql").zero?
    end

    def supports_partition_catalog_checks?(connection)
      connection.adapter_name.casecmp("postgresql").zero?
    end
  end

  class SequelLikeModel
  end

  before do
    ActiveVersion.clear_context!
    ActiveVersion.reset_runtime_adapter!
  end

  after do
    ActiveVersion.reset_runtime_adapter!
  end

  it "passes runtime contract validation" do
    adapter = SequelLikeRuntimeAdapter.new(base_db: SequelLikeDatabase.new)

    expect(ActiveVersion::Runtime.valid_adapter?(adapter)).to eq(true)
  end

  it "supports context and test transaction querying through Sequel-like wrappers" do
    base_db = SequelLikeDatabase.new(adapter_name: "PostgreSQL")
    adapter = SequelLikeRuntimeAdapter.new(base_db: base_db)
    ActiveVersion.runtime_adapter = adapter

    ActiveVersion.with_context(user_agent: "sequel-like") do
      expect(ActiveVersion.context[:user_agent]).to eq("sequel-like")
    end

    expect(current_transaction_id).to eq("sequel-like-tx-id")
    expect(base_db.sql_log.any? { |sql| sql.include?("SET LOCAL active_version.context") }).to eq(true)
    expect(base_db.sql_log).to include("SELECT pg_current_xact_id()")
  end

  it "routes with_connection through Sequel-like runtime adapter" do
    routed_db = SequelLikeDatabase.new(adapter_name: "SQLite")
    adapter = SequelLikeRuntimeAdapter.new(base_db: SequelLikeDatabase.new, routed_db: routed_db)
    ActiveVersion.runtime_adapter = adapter

    yielded = nil
    ActiveVersion.with_connection(SequelLikeModel, :audits) { |conn| yielded = conn }

    expect(yielded.adapter_name).to eq("Sqlite")
  end
end
