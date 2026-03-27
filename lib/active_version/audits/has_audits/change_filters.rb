require "json"

module ActiveVersion
  module Audits
    module HasAudits
      # Methods for filtering and processing changes
      module ChangeFilters
        extend ActiveSupport::Concern

        private

        def audited_changes(for_touch: false, exclude_readonly_attrs: false)
          all_changes = if for_touch
            # For touch operations, use changes that will be saved
            respond_to?(:changes_to_save) ? changes_to_save : changes
          elsif persisted?
            # For updates to persisted records, use changes that will be saved
            (respond_to?(:changes_to_save) && !changes_to_save.empty?) ? changes_to_save : changes
          else
            # For new records, use all changes
            changes
          end

          all_changes = all_changes.except(*self.class.readonly_attributes.to_a) if exclude_readonly_attrs

          # Filter by only/except options
          filtered_changes = if audited_options[:only].present?
            all_changes.slice(*audited_options[:only])
          else
            all_changes.except(*non_audited_columns)
          end

          # Normalize, redact, and filter
          filtered_changes = normalize_enum_changes(filtered_changes)
          filtered_changes = redact_values(filtered_changes)
          filtered_changes = filter_encrypted_attrs(filtered_changes)
          filtered_changes.to_hash
        end

        def audited_attributes
          attrs = attributes.except(*non_audited_columns)
          attrs = redact_values(attrs)
          attrs = filter_encrypted_attrs(attrs)
          normalize_enum_changes(attrs)
        end

        def non_audited_columns
          @non_audited_columns ||= begin
            default_ignored = [self.class.primary_key, self.class.inheritance_column] | ActiveVersion.config.ignored_attributes.map(&:to_s)
            if audited_options[:only].present?
              (self.class.column_names | default_ignored) - audited_options[:only]
            elsif audited_options[:except].present?
              default_ignored | audited_options[:except]
            else
              default_ignored
            end
          end
        end

        def normalize_enum_changes(changes)
          return changes if ActiveVersion.config.store_synthesized_enums

          self.class.defined_enums.each do |name, values|
            next unless changes.has_key?(name)

            changes[name] = if changes[name].is_a?(Array)
              changes[name].map { |v| values[v] }
            else
              values[changes[name]]
            end
          end
          changes
        end

        def redact_values(filtered_changes)
          filter_attr_values(
            audited_changes: filtered_changes,
            attrs: audited_options[:redacted],
            placeholder: audited_options[:redaction_value] || REDACTED
          )
        end

        def filter_encrypted_attrs(filtered_changes)
          return filtered_changes unless respond_to?(:encrypted_attributes)

          filter_attr_values(
            audited_changes: filtered_changes,
            attrs: Array(encrypted_attributes).map(&:to_s),
            placeholder: "[FILTERED]"
          )
        end

        def filter_attr_values(audited_changes: {}, attrs: [], placeholder: "[FILTERED]")
          attrs.each do |attr|
            next unless audited_changes.key?(attr)

            changes = audited_changes[attr]
            values = changes.is_a?(Array) ? changes.map { placeholder } : placeholder

            audited_changes[attr] = values
          end

          audited_changes
        end

        def prepare_sql_values(changes)
          h = changes.each_with_object({}) do |(k, v), acc|
            acc[k] = v.last if v.is_a?(Array)
            acc[k] = v unless v.is_a?(Array)
            acc[k] = JSON.generate(acc[k]) if acc[k].is_a?(Hash) || acc[k].is_a?(Array)
          end
          # Arel INSERT uses keys as column names; stringify so :action / mirror :attrs match
          # string keys from column_mapper and so symbol + string for the same column cannot
          # both appear (PG::DuplicateColumn).
          h.transform_keys(&:to_s)
        end
      end
    end
  end
end
