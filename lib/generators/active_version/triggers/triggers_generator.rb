require "rails/generators"
require "rails/generators/active_record"

module ActiveVersion
  module Generators
    class TriggersGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :type,
        type: :string,
        default: "audit",
        desc: "Trigger type: audit or revision"

      class_option :events,
        type: :array,
        default: ["insert", "update", "delete"],
        desc: "Events to trigger on (for audits)"

      def generate_trigger_migration_file
        migration_template "migration.rb.erb",
          File.join("db/migrate", "add_#{type}_trigger_to_#{table_name}.rb"),
          migration_version: migration_version
      end

      private

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end

      def table_name
        file_name.pluralize
      end

      def type
        options[:type] || "audit"
      end

      def events
        options[:events] || ["insert", "update", "delete"]
      end

      def trigger_function_name
        "active_version_#{type}_#{table_name}"
      end

      def trigger_name
        "active_version_#{type}_on_#{table_name}"
      end

      def audit_table_name
        "#{table_name}_audits"
      end

      def revision_table_name
        "#{table_name}_revisions"
      end

      def auditable_type
        file_name.classify
      end

      def tracked_columns
        return [] unless ActiveRecord::Base.connected?

        ActiveRecord::Base.connection.columns(table_name).map(&:name)
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, StandardError
        []
      end
    end
  end
end
