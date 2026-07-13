require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion core helpers" do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    ActiveVersion.clear_context!
    ActiveVersion.config.execution_scope = :fiber
    ActiveVersion.auditing_enabled = true
    ActiveVersion.reset_runtime_adapter!
  end

  it "yields config in configure and returns configuration" do
    yielded = nil
    returned = ActiveVersion.configure { |cfg| yielded = cfg }

    expect(yielded).to eq(ActiveVersion.config)
    expect(returned).to eq(ActiveVersion.config)
  end

  it "accepts nil context in with_context and defaults to empty hash" do
    ActiveVersion.with_context(nil) do
      expect(ActiveVersion.context).to eq({})
    end
  end

  it "raises when with_context receives non-hash context" do
    expect do
      ActiveVersion.with_context("bad") { nil }
    end.to raise_error(ArgumentError, /context must be a hash/)
  end

  it "dispatches to transactional context path when supported" do
    allow(ActiveVersion).to receive(:transactional_context_supported?).and_return(true)
    expect(ActiveVersion).to receive(:with_transactional_context).with({ip: "1"}).and_yield

    ActiveVersion.with_context(ip: "1") { nil }
  end

  it "uses fiber-local store when execution_scope is :fiber" do
    ActiveVersion.config.execution_scope = :fiber

    ActiveVersion.store_set(:active_version_test_key, "fiber-value")
    expect(ActiveVersion.store_get(:active_version_test_key)).to eq("fiber-value")
  end

  it "uses thread-variable keys when execution_scope is :thread" do
    ActiveVersion.config.execution_scope = :thread
    Thread.current.thread_variable_set(:active_version_thread_key, "thread-value")

    keys = ActiveVersion.send(:store_keys)
    expect(keys).to include(:active_version_thread_key)
  ensure
    Thread.current.thread_variable_set(:active_version_thread_key, nil)
  end

  it "executes transactional context setup and restore with open transaction" do
    connection = instance_double("Connection")
    allow(connection).to receive(:open_transactions).and_return(1)
    allow(connection).to receive(:quote) { |value| "'#{value}'" }
    allow(connection).to receive(:execute)
    allow(connection).to receive(:adapter_name).and_return("PostgreSQL")
    runtime_adapter = instance_double("RuntimeAdapter", base_connection: connection)
    allow(ActiveVersion::Runtime).to receive(:adapter).and_return(runtime_adapter)

    ActiveVersion.send(:with_transactional_context, {ip: "127.0.0.1"}) do
      expect(ActiveVersion.context[:ip]).to eq("127.0.0.1")
    end

    expect(connection).to have_received(:execute).with(/SET LOCAL active_version\.context/)
    expect(ActiveVersion.context[:ip]).to be_nil
  end

  it "temporarily disables and restores auditing in without_auditing" do
    ActiveVersion.auditing_enabled = true

    ActiveVersion.without_auditing do
      expect(ActiveVersion.auditing_enabled).to eq(false)
    end

    expect(ActiveVersion.auditing_enabled).to eq(true)
  end

  it "disables and enables auditing directly" do
    ActiveVersion.disable_auditing
    expect(ActiveVersion.auditing_enabled).to eq(false)

    ActiveVersion.enable_auditing
    expect(ActiveVersion.auditing_enabled).to eq(true)
  end

  it "keeps connection helpers as pass-through behavior" do
    expect(ActiveVersion.connection_for(Post, :audits)).to eq(:default)
    expect(ActiveVersion.adapter_for(Post, :audits)).to eq(Post.connection)

    yielded = nil
    result = ActiveVersion.with_connection(Post, :audits) do |conn|
      yielded = conn
      :ok
    end

    expect(yielded).to eq(Post.connection)
    expect(result).to eq(:ok)
  end

  it "delegates connection adapter helpers to runtime adapter" do
    connection = instance_double("Connection")
    runtime_adapter = instance_double("RuntimeAdapter")
    allow(runtime_adapter).to receive(:connection_for).with(Post, :revisions).and_return(connection)
    allow(ActiveVersion::Runtime).to receive(:adapter).and_return(runtime_adapter)

    expect(ActiveVersion.adapter_for(Post, :revisions)).to eq(connection)
    yielded = nil
    result = ActiveVersion.with_connection(Post, :revisions) do |conn|
      yielded = conn
      :ok
    end

    expect(yielded).to eq(connection)
    expect(result).to eq(:ok)
  end

  it "logs debug messages through ActiveVersion.logger" do
    logger = instance_double("Logger")
    allow(logger).to receive(:debug)
    previous = ActiveVersion.logger
    ActiveVersion.logger = logger

    ActiveVersion.log_debug("test message")

    expect(logger).to have_received(:debug).with("test message")
  ensure
    ActiveVersion.logger = previous
  end

  it "exposes runtime adapter setter/getter and reset helpers" do
    custom = Class.new do
      def base_connection = nil
      def connection_for(_model_class, _version_type) = nil
    end.new

    ActiveVersion.runtime_adapter = custom
    expect(ActiveVersion.runtime_adapter).to eq(custom)

    ActiveVersion.reset_runtime_adapter!
    expect(ActiveVersion.runtime_adapter).to be_a(ActiveVersion::Runtime::ActiveRecordAdapter)
  end
end
