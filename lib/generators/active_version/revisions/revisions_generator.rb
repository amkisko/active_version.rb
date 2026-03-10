require "rails/generators"
require "rails/generators/active_record"

module ActiveVersion
  module Generators
    class RevisionsGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :backfill,
        type: :boolean,
        default: false,
        desc: "Create initial snapshots for existing records"

      def create_revision_model
        template "revision_model.rb.erb",
          File.join("app/models", class_path, "#{file_name}_revision.rb")
      end

      def generate_migration_file
        migration_template "migration.rb.erb",
          File.join("db/migrate", "create_#{table_name}.rb"),
          migration_version: migration_version
      end

      def inject_has_revisions
        model_path = File.join("app/models", class_path, "#{file_name}.rb")
        return unless File.exist?(model_path)

        inject_into_class(model_path, class_name) do
          "  has_revisions\n"
        end
      end

      def create_backfill_migration
        return unless options[:backfill]

        migration_template "backfill_migration.rb.erb",
          File.join("db/migrate", "backfill_#{table_name}.rb"),
          migration_version: migration_version
      end

      private

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end

      def table_name
        "#{file_name}_revisions"
      end

      def revision_class_name
        "#{class_name}Revision"
      end

      def foreign_key
        "#{file_name}_id"
      end

      def version_column
        ActiveVersion.config.revision_version_column
      end

      def source_table_name
        file_name.pluralize
      end
    end
  end
end
