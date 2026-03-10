module ActiveVersion
  module Audits
    module HasAudits
      # Helper methods for database adapter-agnostic operations
      # Relies on ActiveRecord's built-in adapter abstractions
      module DatabaseAdapterHelper
        extend ActiveSupport::Concern

        module ClassMethods
          # Check if a column is a JSON/JSONB type (not text)
          def json_column?(model_class, column_name)
            column = model_class.columns_hash[column_name.to_s]
            return false unless column

            # Check column type
            type = column.type.to_s.downcase
            type == "json" || type == "jsonb"
          end

          # Get adapter-agnostic condition to filter out empty JSON objects
          # Uses ActiveRecord's abstractions (where.not) which handle adapter differences
          def filter_empty_json_condition(relation, column_name, model_class = nil)
            model_class ||= relation.klass
            column = model_class.columns_hash[column_name.to_s]

            # Check column type to determine best approach
            if column
              column_type = column.type.to_s.downcase

              case column_type
              when "jsonb", "json"
                # For JSON/JSONB columns, use string comparison
                # ActiveRecord's where.not handles adapter-specific SQL generation
                relation.where.not(column_name => "{}")
              else
                # For TEXT columns, use Arel function for length check
                # ActiveRecord adapters will translate this appropriately
                table = model_class.arel_table
                column_arel = table[column_name.to_sym]
                length_func = Arel::Nodes::NamedFunction.new("LENGTH", [column_arel])
                relation.where(length_func.gt(2))
              end
            else
              # Fallback: use length check via Arel
              table = model_class.arel_table
              column_arel = table[column_name.to_sym]
              length_func = Arel::Nodes::NamedFunction.new("LENGTH", [column_arel])
              relation.where(length_func.gt(2))
            end
          end

          # Get adapter-agnostic condition for checking if JSON is NOT empty
          # Returns an Arel node that can be used in where clauses
          def not_empty_json_condition(column_name, model_class = ActiveRecord::Base)
            column = model_class.columns_hash[column_name.to_s]
            table = model_class.arel_table
            column_arel = table[column_name.to_sym]

            if column
              column_type = column.type.to_s.downcase

              case column_type
              when "jsonb", "json"
                # For JSON/JSONB: use Arel's not_eq - ActiveRecord adapters handle this
                column_arel.not_eq("{}")
              else
                # For TEXT: use Arel function for length (adapter-agnostic)
                length_func = Arel::Nodes::NamedFunction.new("LENGTH", [column_arel])
                length_func.gt(2)
              end
            else
              # Fallback: use length check via Arel
              length_func = Arel::Nodes::NamedFunction.new("LENGTH", [column_arel])
              length_func.gt(2)
            end
          end
        end

        # Instance methods
        def json_column?(column_name)
          self.class.json_column?(self.class, column_name)
        end
      end
    end
  end
end
