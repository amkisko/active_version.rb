require "json"

module ActiveVersion
  module Audits
    # SQL builder for batch audit operations
    module SQLBuilder
      extend ActiveSupport::Concern

      module ClassMethods
        BatchCollector = Struct.new(:records) do
          def <<(record)
            records << record
            self
          end

          def add(record)
            self << record
          end

          def concat(list)
            records.concat(Array(list))
            self
          end

          def to_a
            records
          end
        end

        # Generate SQL for batch insert of audits
        # @param records [Array] Array of ActiveRecord instances to audit
        # @param options [Hash] Options for batch generation
        # @option options [Boolean] :combine (true) Combine into single INSERT statement
        # @option options [Hash] :context Additional context to merge with each audit
        # @return [String] SQL statement(s) for batch insert
        def batch_insert_sql(records = nil, options = {}, &block)
          records, options = normalize_batch_arguments(records, options)
          captured_values = []

          if block_given? && block.arity == 0 && Array(records).flatten.compact.empty?
            captured_values = capture_audit_values(options) { yield }
          end

          if captured_values.any?
            if options[:combine] != false
              return build_combined_insert_sql(self, captured_values)
            end

            return captured_values.map { |values| build_single_insert_sql(self, values) }.join(";\n")
          end

          records = resolve_batch_records(records, &block)
          return "" if records.empty?

          # Get audit class from first record
          first_record = records.first
          return "" unless first_record

          audit_class = first_record.class.audit_class
          return "" unless audit_class

          version_tracker = {}

          # Build values for each record
          values_list = records.map do |record|
            build_batch_audit_values(record, audit_class, options, version_tracker)
          end.compact

          return "" if values_list.empty?

          # Combine into single INSERT with multiple VALUES
          if options[:combine] != false
            build_combined_insert_sql(audit_class, values_list)
          else
            # Return separate INSERT statements
            values_list.map do |values|
              build_single_insert_sql(audit_class, values)
            end.join(";\n")
          end
        end

        # Execute batch insert SQL for audits.
        # Supports the same arguments and block semantics as batch_insert_sql.
        # @return [Integer] 0 when nothing to insert, otherwise adapter execute result
        def batch_insert(records = nil, options = {}, &block)
          sql = batch_insert_sql(records, options, &block)
          return 0 if sql.empty?

          connection.execute(sql)
        end

        private

        def normalize_batch_arguments(records, options)
          if records.is_a?(Hash) && options.empty?
            [nil, records]
          else
            [records, options]
          end
        end

        def resolve_batch_records(records, &block)
          return Array(records).flatten.compact unless block_given?

          collected = []
          if block.arity == 1
            yield(BatchCollector.new(collected))
          else
            yield
          end

          Array(collected).flatten.compact
        end

        def capture_audit_values(options = {})
          previous_state = ActiveVersion.store_get(:active_version_audit_batch_state)
          state = {
            target_audit_class: self,
            options: options,
            values: [],
            version_tracker: {}
          }
          ActiveVersion.store_set(:active_version_audit_batch_state, state)
          yield
          state[:values]
        ensure
          ActiveVersion.store_set(:active_version_audit_batch_state, previous_state)
        end

        def build_batch_audit_values(record, audit_class, options, version_tracker)
          # Allow building values even if record hasn't changed (for testing/documentation)
          return nil unless record.changed? || options[:force] || options[:allow_saved]

          # Determine action
          action = if record.new_record?
            "create"
          elsif options[:destroy]
            "destroy"
          else
            "update"
          end

          # Get audited changes
          changes = record.send(:audited_changes) if record.respond_to?(:audited_changes, true)
          changes ||= record.changes

          # Build base attributes
          attrs = {
            action: action,
            audited_changes: changes
          }
          attrs[:comment] = record.audit_comment if record.respond_to?(:audit_comment)

          # Merge context
          global_context = ActiveVersion.context || {}
          instance_context = record.audit_context if record.respond_to?(:audit_context)
          context = global_context.merge(instance_context || {})
          context.merge!(options[:context] || {})
          attrs[:audited_context] = context if context.any?

          # Set polymorphic association
          auditable_column = ActiveVersion.column_mapper.column_for(record.class, :audits, :auditable)
          identity_map = if record.respond_to?(:active_version_audit_identity_map)
            record.active_version_audit_identity_map
          elsif record.respond_to?(:active_version_auditable_id_value)
            {"#{auditable_column}_id" => record.active_version_auditable_id_value}
          else
            {"#{auditable_column}_id" => record.id}
          end
          return nil if identity_map.values.any?(&:nil?)
          attrs.merge!(identity_map)
          attrs["#{auditable_column}_type"] = record.class.name

          # Set version
          version_column = ActiveVersion.column_mapper.column_for(record.class, :audits, :version)
          attrs[version_column] = next_batch_version(
            audit_class,
            version_column,
            "#{auditable_column}_type",
            identity_map,
            attrs["#{auditable_column}_type"],
            version_tracker
          )

          # Set user if available
          user_column = ActiveVersion.column_mapper.column_for(record.class, :audits, :user)
          if user_column && defined?(ActiveVersion::RequestStore) && ActiveVersion::RequestStore.audited_user
            user = ActiveVersion::RequestStore.audited_user
            if user.respond_to?(:id)
              attrs[user_column] = user.id
              if user_column.to_s.end_with?("_id") && user.respond_to?(:class)
                type_column = user_column.to_s.gsub("_id", "_type")
                attrs[type_column] = user.class.name
              end
            end
            # If user doesn't have id method, skip setting user column
          end

          # Set timestamps
          attrs[:created_at] = Time.current
          attrs[:updated_at] = Time.current

          attrs
        end

        def next_batch_version(audit_class, version_column, type_column, identity_map, auditable_type, version_tracker)
          normalized_identity_map = identity_map.transform_keys(&:to_s).sort.to_h
          cache_key = [auditable_type, normalized_identity_map]
          previous_version = version_tracker[cache_key]
          if previous_version
            version_tracker[cache_key] = previous_version + 1
            return version_tracker[cache_key]
          end

          max_version = audit_class
            .where(normalized_identity_map.merge(type_column => auditable_type))
            .maximum(version_column)
            .to_i

          version_tracker[cache_key] = max_version + 1
        end

        def build_combined_insert_sql(audit_class, values_list)
          return "" if values_list.empty?

          # Get all columns from all values
          all_columns = values_list.flat_map(&:keys).uniq
          connection = audit_class.connection
          table_name = connection.quote_table_name(audit_class.table_name)
          column_list = all_columns.map { |col| connection.quote_column_name(col) }.join(", ")

          values_sql = values_list.map do |values|
            row_values = all_columns.map { |col| connection.quote(prepare_sql_value(values[col])) }.join(", ")
            "(#{row_values})"
          end.join(", ")

          "INSERT INTO #{table_name} (#{column_list}) VALUES #{values_sql}"
        end

        def build_single_insert_sql(audit_class, values)
          stmt = Arel::InsertManager.new
          table = Arel::Table.new(audit_class.table_name)
          stmt.into(table)

          values.keys.each { |key| stmt.columns << table[key] }
          stmt.values = stmt.create_values(values.values.map { |v| prepare_sql_value(v) })
          stmt.to_sql
        end

        def prepare_sql_value(value)
          case value
          when Hash, Array
            JSON.generate(value)
          when Time, DateTime
            value.utc
          when Date
            value.to_time.utc
          else
            value
          end
        end
      end
    end
  end
end
