require "spec_helper"

RSpec.describe ActiveVersion::Configuration do
  subject(:config) { described_class.new }

  describe "default values" do
    it "has auditing enabled by default" do
      expect(config.auditing_enabled).to be true
    end

    it "has default current_user_method" do
      expect(config.current_user_method).to eq(:current_user)
    end

    it "uses fiber execution scope by default" do
      expect(config.execution_scope).to eq(:fiber)
    end

    it "has default ignored attributes" do
      expect(config.ignored_attributes).to include("lock_version", "created_at", "updated_at")
    end

    it "has default translation locale column" do
      expect(config.translation_locale_column).to eq(:locale)
    end

    it "has default revision version column" do
      expect(config.revision_version_column).to eq(:version)
    end

    it "has default audit storage" do
      expect(config.audit_storage).to eq(:json_column)
    end

    it "has default audit column names" do
      expect(config.audit_action_column).to eq(:action)
      expect(config.audit_changes_column).to eq(:audited_changes)
      expect(config.audit_context_column).to eq(:audited_context)
      expect(config.audit_comment_column).to eq(:comment)
      expect(config.audit_version_column).to eq(:version)
    end

    it "fails fast on audit and revision write errors by default" do
      expect(config.audit_error_behavior).to eq(:exception)
      expect(config.revision_error_behavior).to eq(:exception)
    end
  end

  describe "#validate!" do
    context "with valid configuration" do
      it "does not raise an error" do
        expect { config.validate! }.not_to raise_error
      end
    end

    context "with invalid audit storage" do
      it "raises ConfigurationError" do
        config.audit_storage = :invalid
        expect { config.validate! }.to raise_error(ActiveVersion::ConfigurationError)
      end
    end

    context "with invalid column name type" do
      it "raises ConfigurationError" do
        config.audit_action_column = 123
        expect { config.validate! }.to raise_error(ActiveVersion::ConfigurationError)
      end
    end

    context "with invalid execution scope" do
      it "raises ConfigurationError" do
        config.execution_scope = :invalid
        expect { config.validate! }.to raise_error(ActiveVersion::ConfigurationError)
      end
    end
  end
end
