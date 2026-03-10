module ActiveVersion
  module Revisions
    # SQL builder for batch revision operations
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

        # Generate SQL for batch insert of revisions
        # @param records [Array] Array of ActiveRecord instances
        # @param options [Hash] Options for batch generation
        # @option options [Integer] :version Version number to use
        # @option options [Boolean] :combine (true) Combine into single INSERT statement
        # @option options [Boolean] :force (false) Include non-dirty records
        # @option options [Boolean] :allow_saved (false) Alias for force semantics
        # @return [String] SQL statement(s) for batch insert
        def batch_insert_sql(records = nil, options = {}, &block)
          records, options = normalize_batch_arguments(records, options)
          captured_values = []
          block_consumed = false

          if block_given? && Array(records).flatten.compact.empty?
            collected = []
            captured_values = capture_revision_values(options) do
              if block.arity == 1
                yield(BatchCollector.new(collected))
              else
                yield
              end
            end
            records = collected
            block_consumed = true
          end

          if Array(records).flatten.compact.empty? && captured_values.any?
            revision_class = self
            version_column = revision_class.revision_column_for(:version)
            conflict_target = Array(revision_class.source_foreign_key) + [version_column]

            if options[:combine] != false
              return build_combined_insert_sql(
                revision_class,
                captured_values,
                upsert: options[:upsert] == true,
                conflict_target: conflict_target
              )
            end

            return captured_values.map do |values|
              build_single_insert_sql(
                revision_class,
                values,
                upsert: options[:upsert] == true,
                conflict_target: conflict_target
              )
            end.join(";\n")
          end

          records = if block_consumed
            Array(records).flatten.compact
          else
            resolve_batch_records(records, &block)
          end
          return "" if records.empty?

          revision_class = records.first.class.revision_class
          return "" unless revision_class

          version = options[:version] || 1
          upsert = options[:upsert] == true
          foreign_keys = Array(revision_class.source_foreign_key)
          version_column = ActiveVersion.column_mapper.column_for(records.first.class, :revisions, :version)

          # Build values for each record
          values_list = records.map do |record|
            build_batch_revision_values(record, revision_class, foreign_keys, version_column, version, options)
          end.compact

          return "" if values_list.empty?

          # Combine into single INSERT with multiple VALUES
          if options[:combine] != false
            build_combined_insert_sql(
              revision_class,
              values_list,
              upsert: upsert,
              conflict_target: foreign_keys + [version_column]
            )
          else
            # Return separate INSERT statements
            values_list.map do |values|
              build_single_insert_sql(
                revision_class,
                values,
                upsert: upsert,
                conflict_target: foreign_keys + [version_column]
              )
            end.join(";\n")
          end
        end

        # Execute batch insert SQL for revisions.
        # Supports the same arguments and block semantics as batch_insert_sql.
        # @return [Integer] 0 when nothing to insert, otherwise adapter execute result
        def batch_insert(records = nil, options = {}, &block)
          sql = batch_insert_sql(records, options, &block)
          return 0 if sql.empty?

          connection.execute(sql)
        end

        # Generate SQL for batch upsert of revisions.
        # Uses (source_foreign_key, version_column) conflict target.
        def batch_upsert_sql(records, options = {})
          batch_insert_sql(records, options.merge(upsert: true))
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

        def capture_revision_values(options = {})
          previous_state = ActiveVersion.store_get(:active_version_revision_batch_state)
          state = {
            target_revision_class: self,
            options: options,
            values: [],
            version_tracker: {}
          }
          ActiveVersion.store_set(:active_version_revision_batch_state, state)
          yield
          state[:values]
        ensure
          ActiveVersion.store_set(:active_version_revision_batch_state, previous_state)
        end

        def build_batch_revision_values(record, revision_class, foreign_keys, version_column, version, options = {})
          return nil unless record.changed? || options[:force] || options[:allow_saved]

          # Get all attributes except metadata
          attrs = record.attributes.except("id", "created_at", "updated_at")
          identity_map = if record.respond_to?(:active_version_revision_identity_map)
            record.active_version_revision_identity_map
          else
            keys = Array(foreign_keys).map(&:to_s)
            if keys.length == 1
              {keys.first => record.id}
            else
              values = Array(record.class.primary_key).map { |column| record[column] }
              keys.zip(values).to_h
            end
          end
          attrs.merge!(identity_map)
          attrs[version_column] = version
          attrs[:created_at] = Time.current
          attrs[:updated_at] = Time.current

          attrs
        end

        def build_combined_insert_sql(revision_class, values_list, upsert: false, conflict_target: [])
          return "" if values_list.empty?

          # Get all columns from all values
          all_columns = values_list.flat_map(&:keys).uniq
          connection = revision_class.connection
          table_name = connection.quote_table_name(revision_class.table_name)
          column_list = all_columns.map { |col| connection.quote_column_name(col) }.join(", ")

          values_sql = values_list.map do |values|
            row_values = all_columns.map { |col| connection.quote(prepare_sql_value(values[col])) }.join(", ")
            "(#{row_values})"
          end.join(", ")

          sql = "INSERT INTO #{table_name} (#{column_list}) VALUES #{values_sql}"
          return sql unless upsert

          updatable_columns = all_columns.map(&:to_s) - conflict_target.map(&:to_s) - ["id", "created_at"]
          if updatable_columns.empty?
            "#{sql} ON CONFLICT (#{conflict_target.map { |col| connection.quote_column_name(col) }.join(", ")}) DO NOTHING"
          else
            assignments = updatable_columns.map do |col|
              qcol = connection.quote_column_name(col)
              "#{qcol} = EXCLUDED.#{qcol}"
            end.join(", ")
            "#{sql} ON CONFLICT (#{conflict_target.map { |col| connection.quote_column_name(col) }.join(", ")}) DO UPDATE SET #{assignments}"
          end
        end

        def build_single_insert_sql(revision_class, values, upsert: false, conflict_target: [])
          stmt = Arel::InsertManager.new
          table = Arel::Table.new(revision_class.table_name)
          stmt.into(table)

          values.keys.each { |key| stmt.columns << table[key] }
          stmt.values = stmt.create_values(values.values.map { |v| prepare_sql_value(v) })
          sql = stmt.to_sql
          return sql unless upsert

          connection = revision_class.connection
          updatable_columns = values.keys.map(&:to_s) - conflict_target.map(&:to_s) - ["id", "created_at"]
          if updatable_columns.empty?
            "#{sql} ON CONFLICT (#{conflict_target.map { |col| connection.quote_column_name(col) }.join(", ")}) DO NOTHING"
          else
            assignments = updatable_columns.map do |col|
              qcol = connection.quote_column_name(col)
              "#{qcol} = EXCLUDED.#{qcol}"
            end.join(", ")
            "#{sql} ON CONFLICT (#{conflict_target.map { |col| connection.quote_column_name(col) }.join(", ")}) DO UPDATE SET #{assignments}"
          end
        end

        def prepare_sql_value(value)
          case value
          when Hash, Array
            value.to_json
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
