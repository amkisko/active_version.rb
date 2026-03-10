require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe ActiveVersion::Sharding::ConnectionRouter do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  let(:model_class) { Post }

  describe ".connection_for" do
    it "always returns :default" do
      expect(described_class.connection_for(model_class, :audits)).to eq(:default)
      expect(described_class.connection_for(model_class, :revisions)).to eq(:default)
      expect(described_class.connection_for(model_class, :translations)).to eq(:default)
    end
  end

  describe ".adapter_for" do
    it "returns the model connection" do
      expect(described_class.adapter_for(model_class, :audits)).to eq(model_class.connection)
    end

    it "delegates to ActiveVersion adapter routing" do
      routed = instance_double("Connection")
      allow(ActiveVersion).to receive(:adapter_for).with(model_class, :audits).and_return(routed)

      expect(described_class.adapter_for(model_class, :audits)).to eq(routed)
    end
  end

  describe ".with_connection" do
    it "yields the model connection and returns block result" do
      yielded = nil
      result = described_class.with_connection(model_class, :audits) do |conn|
        yielded = conn
        :ok
      end

      expect(yielded).to eq(model_class.connection)
      expect(result).to eq(:ok)
    end

    it "delegates block execution to ActiveVersion connection helper" do
      routed = instance_double("Connection")
      allow(ActiveVersion).to receive(:with_connection).with(model_class, :audits).and_yield(routed)

      yielded = nil
      described_class.with_connection(model_class, :audits) { |conn| yielded = conn }

      expect(yielded).to eq(routed)
    end
  end
end
