require "rails/generators"
require "rails/generators/active_record"

module ActiveVersion
  module Generators
    class TranslationsGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :attributes, type: :array, default: [], banner: "field:type field:type"

      class_option :translated_attributes,
        type: :array,
        default: [],
        desc: "Attributes to translate (e.g., title:string body:text)"

      def create_translation_model
        template "translation_model.rb.erb",
          File.join("app/models", class_path, "#{file_name}_translation.rb")
      end

      def generate_migration_file
        migration_template "migration.rb.erb",
          File.join("db/migrate", "create_#{table_name}.rb"),
          migration_version: migration_version
      end

      def inject_has_translations
        model_path = File.join("app/models", class_path, "#{file_name}.rb")
        return unless File.exist?(model_path)

        inject_into_class(model_path, class_name) do
          "  has_translations\n"
        end
      end

      private

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end

      def table_name
        "#{file_name}_translations"
      end

      def translation_class_name
        "#{class_name}Translation"
      end

      def foreign_key
        "#{file_name}_id"
      end

      def locale_column
        ActiveVersion.config.translation_locale_column
      end

      def translated_attributes
        options[:translated_attributes] || []
      end

      def migration_attributes
        translated_attributes.map do |attr|
          name, type = attr.split(":")
          type ||= "string"
          "t.#{type} :#{name}"
        end
      end
    end
  end
end
