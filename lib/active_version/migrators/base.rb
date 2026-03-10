module ActiveVersion
  module Migrators
    # Base migrator for converting from other versioning libraries
    class Base
      AUDIT_STORAGES = %i[json_column yaml_column mirror_columns].freeze

      class << self
        # Migrate data from another library
        # @param model_class [Class] ActiveRecord model class
        # @param options [Hash] Migration options
        # @return [Integer] Number of records migrated
        def migrate(model_class, options = {})
          raise NotImplementedError, "Subclasses must implement migrate"
        end

        # Migration helper for creating audit tables
        def create_audit_table(table_name, options = {})
          table_options = options.dup
          storage = normalize_audit_storage(table_options.delete(:storage))
          mirror_columns = normalize_mirror_columns(table_options.delete(:mirror_columns))
          changes_column = (table_options.delete(:changes_column) || :audited_changes).to_sym
          context_column = (table_options.delete(:context_column) || :audited_context).to_sym

          create_table_with_plan(
            table_name,
            table_options,
            audit_table_plan(
              table_name: table_name,
              storage: storage,
              mirror_columns: mirror_columns,
              changes_column: changes_column,
              context_column: context_column
            )
          )
        end

        # Migration helper for creating revision tables
        def create_revision_table(table_name, options = {})
          create_table_with_plan(table_name, options.dup, revision_table_plan(table_name))
        end

        # Migration helper for creating translation tables
        def create_translation_table(table_name, options = {})
          create_table_with_plan(table_name, options.dup, translation_table_plan(table_name))
        end

        protected

        # Get source records to migrate
        def source_records(model_class, options = {})
          model_class.all
        end

        # Create audit from source data
        def create_audit(record, audit_data, audit_class)
          audit_class.create!(audit_data)
        end

        # Create revision from source data
        def create_revision(record, revision_data, revision_class)
          revision_class.create!(revision_data)
        end

        # Create translation from source data
        def create_translation(record, translation_data, translation_class)
          translation_class.create!(translation_data)
        end

        private

        def create_table_with_plan(table_name, table_options, plan)
          ActiveRecord::Schema.define do
            create_table table_name, **table_options do |t|
              plan.fetch(:columns).each { |column_builder| column_builder.call(t) }
            end

            plan.fetch(:indexes).each do |(columns, index_options)|
              add_index table_name, columns, **index_options
            end
          end
        end

        def audit_table_plan(table_name:, storage:, mirror_columns:, changes_column:, context_column:)
          payload_type = payload_column_type_for(storage)
          columns = [
            ->(t) { t.references :auditable, polymorphic: true, null: false, index: false },
            ->(t) { t.string :action, null: false },
            ->(t) { t.integer :version, null: false },
            ->(t) { t.references :user, polymorphic: true },
            ->(t) { t.references :associated, polymorphic: true },
            ->(t) { t.text :comment },
            ->(t) { t.string :remote_address },
            ->(t) { t.string :request_uuid }
          ]

          if storage == :mirror_columns
            mirror_columns.each do |column_name, type|
              columns << ->(t) { t.public_send(type, column_name) }
            end
          else
            columns << ->(t) { t.public_send(payload_type, context_column) }
            columns << ->(t) { t.public_send(payload_type, changes_column) }
          end

          columns << ->(t) { t.timestamps }

          {
            columns: columns,
            indexes: [
              [[:auditable_type, :auditable_id, :version], {unique: true, name: "index_#{table_name}_on_auditable_and_version"}]
            ]
          }
        end

        def revision_table_plan(table_name)
          {
            columns: [
              ->(t) { t.references :source, polymorphic: true, null: false, index: false },
              ->(t) { t.integer :version, null: false },
              ->(t) { t.text :comment },
              ->(t) { t.timestamps }
            ],
            indexes: [
              [[:source_type, :source_id, :version], {unique: true, name: "index_#{table_name}_on_source_and_version"}]
            ]
          }
        end

        def translation_table_plan(table_name)
          {
            columns: [
              ->(t) { t.references :source, polymorphic: true, null: false, index: false },
              ->(t) { t.string :locale, null: false },
              ->(t) { t.timestamps }
            ],
            indexes: [
              [[:source_type, :source_id, :locale], {unique: true, name: "index_#{table_name}_on_source_and_locale"}]
            ]
          }
        end

        def normalize_audit_storage(value)
          storage = (value || ActiveVersion.config.audit_storage).to_sym
          return storage if AUDIT_STORAGES.include?(storage)

          raise ActiveVersion::ConfigurationError,
            "Unknown audit storage #{storage.inspect}. Expected one of: #{AUDIT_STORAGES.join(", ")}"
        end

        def normalize_mirror_columns(value)
          case value
          when Hash
            value.each_with_object({}) do |(column_name, type), result|
              result[column_name.to_sym] = (type || :text).to_sym
            end
          when Array
            value.each_with_object({}) do |column_name, result|
              result[column_name.to_sym] = :text
            end
          when nil
            {}
          else
            raise ArgumentError, "mirror_columns must be a Hash, Array, or nil"
          end
        end

        def payload_column_type_for(storage)
          return :text if storage == :yaml_column
          return :text unless storage == :json_column
          return :jsonb if adapter_supports_native_type?(:jsonb)
          return :json if adapter_supports_native_type?(:json)

          :text
        end

        def adapter_supports_native_type?(type)
          native_types = current_connection&.native_database_types
          native_types.is_a?(Hash) && native_types.key?(type)
        end

        def current_connection
          return unless defined?(::ActiveRecord::Base)

          ::ActiveRecord::Base.connection
        rescue *ActiveVersion::Runtime.active_record_connection_errors
          nil
        end
      end
    end
  end
end
