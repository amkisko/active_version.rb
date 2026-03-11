require "json"

module ActiveVersion
  module Audits
    module HasAudits
      # Methods for combining audits
      module AuditCombiner
        extend ActiveSupport::Concern

        private

        def combine_audits_if_needed
          max_audits = evaluate_max_audits
          return unless max_audits && max_audits > 0
          changes_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :changes)
          return unless self.class.audit_class.column_names.include?(changes_column.to_s)

          # Keep combining until we're under the limit
          # This handles cases where multiple combinations are needed
          max_iterations = 10 # Safety limit to prevent infinite loops
          iteration = 0

          loop do
            iteration += 1
            break if iteration > max_iterations

            # Force reload from database to see any updates
            if persisted?
              reload
            end

            # Clear association cache to ensure we get fresh data from database.
            # Avoid calling audits reader directly here to prevent AR 6.1
            # delegation edge cases on dynamic models.
            if respond_to?(:association) && association_cached?(:audits)
              association(:audits).reset
            end

            # Get all audits fresh from database (not from cache)
            # Query directly to ensure we get updated values after SQL updates
            auditable_type = audited_options[:class_name] || self.class.name
            auditable_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :auditable)
            version_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :version)
            audit_klass =
              if self.class.reflect_on_association(:audits)
                association(:audits).klass
              else
                self.class.audit_class
              end
            if audit_klass.nil? && self.class.respond_to?(:resolve_audit_class_option, true)
              audit_klass = self.class.send(:resolve_audit_class_option, audited_options[:as])
            end
            break unless audit_klass
            all_audits = audit_klass.where({"#{auditable_column}_type" => auditable_type}.merge(active_version_audit_identity_map))
              .order(version_column => :asc)
              .to_a

            # Filter out combined audits (those with empty changes)
            # Check raw column value first (before JSON parsing) for "{}" string
            active_audits = all_audits.reject do |audit|
              # Check raw column value first - combined audits have "{}" as string
              raw_changes = audit.read_attribute(changes_column)

              # If raw value is exactly "{}", it's a combined audit
              if raw_changes.is_a?(String) && raw_changes.strip == "{}"
                true
              else
                # Otherwise check parsed value
                changes = audit.audited_changes
                changes.nil? || (changes.is_a?(Hash) && changes.empty?) || (changes.is_a?(String) && changes.strip.empty?)
              end
            end

            audits_count = active_audits.length
            break if audits_count <= max_audits

            # Calculate how many extra audits we have
            extra_count = audits_count - max_audits

            # Get the oldest active audits to combine (first extra_count + 1)
            # The +1 is because we'll merge into the last one in this set
            audits_to_combine = active_audits.first(extra_count + 1)

            # Safety check to prevent infinite loops
            break if audits_to_combine.empty? || audits_to_combine.length <= 1

            # Combine them (this will merge into the last audit and mark older ones as combined)
            combine_audits(audits_to_combine)
          end
        end

        def evaluate_max_audits
          max_audits = case (option = audited_options[:max_audits])
          when Proc then option.call
          when Symbol
            # Try instance method first, then class method
            if respond_to?(option, true)
              send(option)
            elsif self.class.respond_to?(option, true)
              self.class.send(option)
            end
          else
            option
          end

          max_audits ||= ActiveVersion.config.max_audits
          Integer(max_audits).abs if max_audits
        end

        def combine_audits(audits_to_combine)
          return if audits_to_combine.empty?

          # Ensure we have an array (might be a relation or array)
          audits_array = audits_to_combine.is_a?(Array) ? audits_to_combine : audits_to_combine.to_a
          return if audits_array.empty?

          combine_target = audits_array.last
          audit_class = combine_target.class
          version_column = ActiveVersion.column_mapper.column_for(combine_target.class.source_class, :audits, :version)
          changes_column = ActiveVersion.column_mapper.column_for(combine_target.class.source_class, :audits, :changes)
          return unless audit_class.column_names.include?(changes_column.to_s)
          context_column = ActiveVersion.column_mapper.column_for(combine_target.class.source_class, :audits, :context)

          # Get changes from each audit - use read_attribute to get raw JSON, then parse
          all_changes = audits_array.map do |a|
            value = a.read_attribute(changes_column)
            # Parse JSON if it's a string
            if value.is_a?(String)
              begin
                JSON.parse(value)
              rescue JSON::ParserError
                {}
              end
            else
              value || {}
            end
          end

          # Merge all changes
          combined_changes = all_changes.reduce({}) { |acc, changes| acc.merge(changes) }

          # Get contexts from each audit
          all_contexts = audits_array.map do |a|
            value = a.read_attribute(context_column)
            if value.is_a?(String)
              begin
                JSON.parse(value)
              rescue JSON::ParserError
                {}
              end
            else
              value || {}
            end
          end.compact

          # Merge contexts
          combined_context = all_contexts.reduce({}) { |acc, ctx| acc.merge(ctx) } if all_contexts.any?

          combine_target_version = combine_target.read_attribute(version_column)

          # Update combine target and mark old audits as combined (no deletion - safer for audit logs)
          audits_to_mark_combined = audits_array[0..-2] # All except the target

          # Update combine target with merged changes using raw SQL to bypass readonly
          conn = audit_class.connection
          table_name = audit_class.table_name
          updates = []
          updates << "#{conn.quote_column_name(changes_column)} = #{conn.quote(JSON.generate(combined_changes))}"
          if combined_context.any?
            updates << "#{conn.quote_column_name(context_column)} = #{conn.quote(JSON.generate(combined_context))}"
          end
          target_id = conn.quote(combine_target.read_attribute(:id))
          sql = "UPDATE #{conn.quote_table_name(table_name)} SET #{updates.join(", ")} WHERE id = #{target_id}"
          conn.execute(sql)

          # Mark old audits as combined (no deletion - safer for audit logs)
          if audits_to_mark_combined.any?
            comment_column = ActiveVersion.column_mapper.column_for(combine_target.class.source_class, :audits, :comment)
            combined_comment = "[COMBINED] This audit was merged into version #{combine_target_version}"

            # Use direct SQL update to bypass readonly enforcement and ensure updates work
            audit_ids = audits_to_mark_combined.map { |a| a.read_attribute(:id) }

            if audit_ids.any?
              # Use raw SQL with proper escaping to bypass ActiveRecord's readonly checks
              conn = audit_class.connection
              table_name = audit_class.table_name
              empty_json_str = JSON.generate({})
              empty_json = conn.quote(empty_json_str)
              quoted_comment = conn.quote(combined_comment)

              # Update all audits in a single SQL statement for efficiency
              id_list = audit_ids.map { |id| conn.quote(id) }.join(",")
              sql = "UPDATE #{conn.quote_table_name(table_name)} SET #{conn.quote_column_name(changes_column)} = #{empty_json}, #{conn.quote_column_name(comment_column)} = #{quoted_comment} WHERE id IN (#{id_list})"

              # Execute the update
              conn.execute(sql)
            end
          end

          # Clear association cache to ensure fresh data is loaded after updates
          if respond_to?(:association) && association_cached?(:audits)
            association(:audits).reset
          end
          begin
            audits.reset
          rescue NoMethodError
            nil
          end
        end
      end
    end
  end
end
