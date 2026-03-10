require "spec_helper"

RSpec.describe ActiveVersion::Translations::HasTranslations do
  # This is a basic structure test - full integration tests would require database setup
  let(:model_class) do
    Class.new(ApplicationRecord) do
      include ActiveVersion::Translations::HasTranslations

      self.table_name = "posts"
      def self.name
        "Post"
      end
    end
  end

  describe ".translation_record?" do
    it "returns false" do
      expect(model_class.translation_record?).to be false
    end
  end

  describe ".translation_class" do
    it "returns the translation class name" do
      # This would require PostTranslation to exist
      expect(model_class.translation_class_name).to eq("PostTranslation")
    end
  end

  describe ".translated_scopes" do
    it "defines scope methods" do
      model_class.translated_scopes(:title)
      expect(model_class).to respond_to(:for_translated_title)
      expect(model_class).to respond_to(:find_by_translated_title)
    end
  end

  describe ".translated_copies" do
    it "defines copy_values_from_translation method" do
      model_class.translated_copies(:title)
      instance = model_class.new
      expect(instance).to respond_to(:copy_values_from_translation)
    end
  end

  describe "#translate" do
    # This would require full database setup with translations
    # For now, just test the method exists
    let(:instance) { model_class.new }

    it "responds to translate method" do
      expect(instance).to respond_to(:translate)
    end
  end

  describe "#translation" do
    let(:instance) { model_class.new }

    it "responds to translation method" do
      expect(instance).to respond_to(:translation)
    end
  end
end
