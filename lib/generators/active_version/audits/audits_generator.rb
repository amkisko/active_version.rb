require "rails/generators"
require "rails/generators/active_record"

module ActiveVersion
  module Generators
    class AuditsGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :storage,
        type: :string,
        default: "json_column",
        desc: "Storage type: json_column, yaml_column, or mirror_columns"

      def create_audit_model
        template "audit_model.rb.erb",
          File.join("app/models", class_path, "#{file_name}_audit.rb")
      end

      def generate_migration_file
        if options[:storage] == "mirror_columns"
          migration_template "migration_table.rb.erb",
            File.join("db/migrate", "create_#{table_name}.rb"),
            migration_version: migration_version
        else
          migration_template "migration_jsonb.rb.erb",
            File.join("db/migrate", "create_#{table_name}.rb"),
            migration_version: migration_version
        end
      end

      def inject_has_audits
        model_path = File.join("app/models", class_path, "#{file_name}.rb")
        return unless File.exist?(model_path)

        inject_into_class(model_path, class_name) do
          "  has_audits\n"
        end
      end

      private

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end

      def table_name
        "#{file_name}_audits"
      end

      def audit_class_name
        "#{class_name}Audit"
      end

      def foreign_key
        "#{file_name}_id"
      end

      def storage_type
        options[:storage] || "json_column"
      end
    end
  end
end
