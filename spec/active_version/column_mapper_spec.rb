require "spec_helper"

RSpec.describe ActiveVersion::ColumnMapper do
  subject(:mapper) { described_class.new }

  let(:model_class) { Class.new(ApplicationRecord) { self.table_name = "posts" } }

  describe "#register" do
    it "registers a column mapping" do
      mapper.register(model_class, :audits, :action, :custom_action)
      expect(mapper.column_for(model_class, :audits, :action)).to eq(:custom_action)
    end
  end

  describe "#column_for" do
    context "with registered mapping" do
      it "returns the registered column name" do
        mapper.register(model_class, :audits, :action, :custom_action)
        expect(mapper.column_for(model_class, :audits, :action)).to eq(:custom_action)
      end
    end

    context "without registered mapping" do
      it "returns default column name" do
        expect(mapper.column_for(model_class, :audits, :action)).to eq(:action)
        expect(mapper.column_for(model_class, :translations, :locale)).to eq(:locale)
        expect(mapper.column_for(model_class, :revisions, :version)).to eq(:version)
      end
    end

    context "with unknown concept" do
      it "raises ConfigurationError for unknown audit concept" do
        expect {
          mapper.column_for(model_class, :audits, :unknown_concept)
        }.to raise_error(ActiveVersion::ConfigurationError, /Unknown audit concept/)
      end

      it "raises ConfigurationError for unknown translation concept" do
        expect {
          mapper.column_for(model_class, :translations, :unknown_concept)
        }.to raise_error(ActiveVersion::ConfigurationError, /Unknown translation concept/)
      end

      it "raises ConfigurationError for unknown revision concept" do
        expect {
          mapper.column_for(model_class, :revisions, :unknown_concept)
        }.to raise_error(ActiveVersion::ConfigurationError, /Unknown revision concept/)
      end
    end

    context "with unknown version type" do
      it "raises ConfigurationError" do
        expect {
          mapper.column_for(model_class, :unknown_type, :action)
        }.to raise_error(ActiveVersion::ConfigurationError)
      end
    end
  end

  describe "#mappings_for" do
    it "returns all mappings for a model and version type" do
      mapper.register(model_class, :audits, :action, :custom_action)
      mapper.register(model_class, :audits, :changes, :custom_changes)

      mappings = mapper.mappings_for(model_class, :audits)
      expect(mappings).to include(action: :custom_action, changes: :custom_changes)
    end

    it "returns empty hash when no mappings exist" do
      mappings = mapper.mappings_for(model_class, :audits)
      expect(mappings).to eq({})
    end

    it "only returns mappings for the specified version type" do
      mapper.register(model_class, :audits, :action, :custom_action)
      mapper.register(model_class, :translations, :locale, :custom_locale)

      audit_mappings = mapper.mappings_for(model_class, :audits)
      expect(audit_mappings).to include(action: :custom_action)
      expect(audit_mappings).not_to include(locale: :custom_locale)
    end
  end

  describe "#register" do
    it "converts column name to symbol" do
      mapper.register(model_class, :audits, :action, "string_column")
      expect(mapper.column_for(model_class, :audits, :action)).to eq(:string_column)
    end
  end

  describe "default column mappings" do
    it "returns default columns for all audit concepts" do
      expect(mapper.column_for(model_class, :audits, :action)).to eq(:action)
      expect(mapper.column_for(model_class, :audits, :changes)).to eq(:audited_changes)
      expect(mapper.column_for(model_class, :audits, :context)).to eq(:audited_context)
      expect(mapper.column_for(model_class, :audits, :comment)).to eq(:comment)
      expect(mapper.column_for(model_class, :audits, :version)).to eq(:version)
      expect(mapper.column_for(model_class, :audits, :user)).to eq(:user_id)
      expect(mapper.column_for(model_class, :audits, :auditable)).to eq(:auditable)
      expect(mapper.column_for(model_class, :audits, :associated)).to eq(:associated)
      expect(mapper.column_for(model_class, :audits, :remote_address)).to eq(:remote_address)
      expect(mapper.column_for(model_class, :audits, :request_uuid)).to eq(:request_uuid)
    end
  end
end
