require "spec_helper"
require "stringio"

RSpec.describe ActiveVersion::VersionRegistry do
  subject(:registry) { described_class.new }

  let(:model_class) { Class.new(ApplicationRecord) { self.table_name = "posts" } }
  let(:version_class) { Class.new(ApplicationRecord) { self.table_name = "post_audits" } }

  describe "#register" do
    it "registers a model with versioning" do
      registry.register(model_class, :audits, {storage: :json_column})
      expect(registry.registered?(model_class, :audits)).to be true
    end

    it "stores options" do
      registry.register(model_class, :audits, {storage: :json_column})
      expect(registry.config_for(model_class, :audits)).to eq({storage: :json_column})
    end

    context "when re-registering with same options" do
      it "allows re-registration without warning" do
        registry.register(model_class, :audits, {storage: :json_column})
        expect {
          registry.register(model_class, :audits, {storage: :json_column})
        }.not_to output.to_stderr
      end
    end

    context "when re-registering with different options" do
      it "warns about option conflicts" do
        registry.register(model_class, :audits, {storage: :json_column})
        io = StringIO.new
        log = Logger.new(io)
        log.formatter = proc { |_, _, _, msg| "#{msg}\n" }
        previous = ActiveVersion.logger
        ActiveVersion.logger = log
        begin
          registry.register(model_class, :audits, {storage: :mirror_columns})
          expect(io.string).to match(/Re-registering.*with different options/)
        ensure
          ActiveVersion.logger = previous
        end
      end

      it "updates to new options" do
        registry.register(model_class, :audits, {storage: :json_column})
        registry.register(model_class, :audits, {storage: :mirror_columns})
        expect(registry.config_for(model_class, :audits)).to eq({storage: :mirror_columns})
      end
    end
  end

  describe "#register_version_class" do
    it "registers a version class" do
      registry.register_version_class(model_class, :audits, version_class)
      expect(registry.version_class_for(model_class, :audits)).to eq(version_class)
    end
  end

  describe "#registered?" do
    context "when registered" do
      it "returns true" do
        registry.register(model_class, :audits)
        expect(registry.registered?(model_class, :audits)).to be true
      end
    end

    context "when not registered" do
      it "returns false" do
        expect(registry.registered?(model_class, :audits)).to be false
      end
    end
  end

  describe "#models_for_version_type" do
    it "returns all models for a version type" do
      model1 = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "Post"
        end
      end
      model2 = Class.new(ApplicationRecord) do
        self.table_name = "comments"
        def self.name
          "Comment"
        end
      end

      registry.register(model1, :audits)
      registry.register(model2, :audits)
      registry.register(model1, :translations)

      models = registry.models_for_version_type(:audits)
      expect(models).to include(model1, model2)
      expect(models.length).to eq(2) # Should only include each model once
    end
  end

  describe "#clear!" do
    it "clears all registrations" do
      registry.register(model_class, :audits)
      registry.register_version_class(model_class, :audits, version_class)

      registry.clear!

      expect(registry.registered?(model_class, :audits)).to be false
      expect(registry.version_class_for(model_class, :audits)).to be_nil
    end
  end
end
