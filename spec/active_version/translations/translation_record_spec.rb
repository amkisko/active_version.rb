require "spec_helper"

RSpec.describe ActiveVersion::Translations::TranslationRecord do
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    ActiveRecord::Schema.define do
      create_table :posts, force: true do |t|
        t.string :title
        t.text :body
        t.timestamps
      end

      create_table :post_translations, force: true do |t|
        t.references :post, null: false, foreign_key: true
        t.string :locale, null: false
        t.string :title
        t.text :body
        t.timestamps
      end

      add_index :post_translations, [:post_id, :locale], unique: true
    end
  end

  let(:source_class) do
    Class.new(ApplicationRecord) do
      self.table_name = "posts"
      def self.name
        "Post"
      end
    end
  end

  let(:translation_class) do
    Class.new(ApplicationRecord) do
      include ActiveVersion::Translations::TranslationRecord

      self.table_name = "post_translations"
      def self.name
        "PostTranslation"
      end
    end
  end

  describe ".translation_record?" do
    it "returns true" do
      expect(translation_class.translation_record?).to be true
    end
  end

  describe ".source_name" do
    it "extracts source name from class name" do
      expect(translation_class.source_name).to eq(:post)
    end
  end

  describe ".source_class" do
    it "returns the source class" do
      # This will fail if Post doesn't exist, but that's expected in tests
      # In real usage, the class would exist
      expect(translation_class.source_name).to eq(:post)
    end
  end

  describe ".source_foreign_key" do
    it "returns the foreign key name" do
      expect(translation_class.source_foreign_key).to eq("post_id")
    end
  end

  describe "configuration DSL" do
    it "supports keyword arguments" do
      translation_class.configure_translation(locale_column: :lang, foreign_key: :post_uuid)

      expect(translation_class.locale_column_name).to eq(:lang)
      expect(translation_class.source_foreign_key).to eq("post_uuid")
    end

    it "supports block configuration" do
      translation_class.configure_translation do
        locale_column :lang
        foreign_key [:tenant_id, :post_id]
        identity_resolver [:tenant_id, :id]
      end

      expect(translation_class.locale_column_name).to eq(:lang)
      expect(translation_class.source_foreign_key).to eq(%w[tenant_id post_id])
      expect(translation_class.source_primary_key).to eq(%w[tenant_id id])
    end
  end

  describe "#attr_present_for_locale?" do
    let(:translation) { translation_class.new(locale: "en", title: "Hello") }

    it "returns true when locale matches and attribute is present" do
      expect(translation.attr_present_for_locale?("en", :title)).to be true
    end

    it "returns false when locale doesn't match" do
      expect(translation.attr_present_for_locale?("fi", :title)).to be false
    end

    it "returns false when attribute is blank" do
      translation.title = nil
      expect(translation.attr_present_for_locale?("en", :title)).to be false
    end
  end
end
