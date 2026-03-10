module ActiveVersion
  module Audits
    module HasAudits
      # Methods for writing audits to the database
      module AuditWriter
        extend ActiveSupport::Concern

        private

        def write_audit(attrs)
          # Capture comment and context before clearing them
          # Use provided context from attrs if available (captured in before_update), otherwise use current
          # Check if context was explicitly passed before deleting
          context_was_provided = attrs.key?(:context)
          provided_context = attrs.delete(:context)
          provided_comment = attrs.delete(:comment)
          captured_comment = provided_comment || audit_comment

          # Merge instance context with global context (instance context takes precedence)
          # Convert keys to strings for consistency
          block_context = ActiveVersion.store_get(:active_version_block_context)
          global_context = if block_context.is_a?(Hash)
            persistent_context = (ActiveVersion.store_get(:active_version_persistent_context) || {}).stringify_keys
            persistent_context.merge(block_context.stringify_keys)
          else
            (ActiveVersion.context || {}).stringify_keys
          end
          # Use provided context if available, otherwise use current audit_context
          # Handle both Hash and other types
          # If context was explicitly provided (even if nil), use it; otherwise fall back to audit_context
          raw_instance_context = if context_was_provided
            provided_context # Could be nil, hash, or other
          else
            audit_context # Fall back to instance variable
          end
          # Normalize instance context to a hash with string keys
          instance_context = if raw_instance_context.nil?
            {}
          elsif raw_instance_context.is_a?(Hash)
            raw_instance_context.stringify_keys
          else
            {}
          end
          # Merge: global context first, then instance context (instance takes precedence)
          captured_context = global_context.dup.merge(instance_context)

          self.audit_comment = nil
          self.audit_context = nil

          if auditing_enabled
            attrs[:associated] = send(audit_associated_with) unless audit_associated_with.nil?

            # Use captured values if not explicitly provided
            attrs[:comment] ||= captured_comment
            # Always set audited_context if it has any values or if context was explicitly provided
            # This ensures instance context is merged with global context even if global context is empty
            # Set it if we have any context (global or instance) or if context was explicitly provided
            if captured_context.present? || context_was_provided || global_context.present?
              attrs[:audited_context] = captured_context
            end

            run_callbacks(:audit) do
              # Build insert attributes
              changes_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :changes)
              context_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :context)
              auditable_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :auditable)
              version_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :version)
              batch_state = ActiveVersion.store_get(:active_version_audit_batch_state)
              batch_capture_active = batch_state.is_a?(Hash) && batch_state[:target_audit_class] == audit_class

              insert_attrs = {}

              # Map action
              insert_attrs[:action] = attrs[:action]

              # Map audited_changes
              changes_column_exists = audit_class.column_names.include?(changes_column.to_s)
              if changes_column_exists
                insert_attrs[changes_column] = attrs[:audited_changes] || attrs[changes_column]
              end

              # For structured table storage, mirror audited fields into dedicated columns.
              if audited_options[:storage].to_sym == :mirror_columns
                # Prefer callback-provided payload so update events use explicit old/new
                # pairs (we persist the "new" side for table columns).
                structured_payload = attrs[:audited_changes] || attrs[changes_column]
                # Fallback for create/destroy or custom flows that do not pass payload.
                structured_payload ||= audited_attributes
                map_structured_audit_columns(insert_attrs, structured_payload)
                copy_shared_source_columns(insert_attrs)
              end

              # Map comment
              comment_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :comment)
              insert_attrs[comment_column] = attrs[:comment] if attrs[:comment].present?

              # Map audited_context
              if attrs[:audited_context].present? || attrs[context_column].present?
                insert_attrs[context_column] = attrs[:audited_context] || attrs[context_column]
              end
              if batch_capture_active
                batch_context = batch_state.dig(:options, :context)
                if batch_context.is_a?(Hash)
                  merged_context = insert_attrs[context_column]
                  merged_context = {} unless merged_context.is_a?(Hash)
                  insert_attrs[context_column] = merged_context.merge(batch_context.stringify_keys)
                end
              end

              # Set polymorphic association
              # In before_update, the record should already have an ID
              # But ensure we have a valid ID before creating the audit
              identity_map = active_version_audit_identity_map
              return nil if identity_map.values.any?(&:nil?) # Skip until identity is fully available

              insert_attrs.merge!(identity_map)
              # Use class_name from options if provided (for dynamically created classes)
              # Otherwise use the actual class name
              auditable_type = audited_options[:class_name] || self.class.name
              if auditable_type.nil?
                raise ConfigurationError, "Cannot determine class name for dynamically created class. Please specify class_name option in has_audits (e.g., has_audits as: PostAudit, class_name: 'Post')"
              end
              insert_attrs["#{auditable_column}_type"] = auditable_type

              # Calculate version number
              if batch_capture_active
                normalized_identity = identity_map.transform_keys(&:to_s).sort.to_h
                tracker_key = [auditable_type, normalized_identity]
                tracker = batch_state[:version_tracker] || {}
                current_version = tracker[tracker_key]

                unless current_version
                  max_version = audit_class.where({"#{auditable_column}_type" => auditable_type}.merge(identity_map))
                    .maximum(version_column) || 0
                  current_version = max_version
                end

                current_version += 1
                tracker[tracker_key] = current_version
                batch_state[:version_tracker] = tracker
                insert_attrs[version_column] = current_version
              elsif attrs[:action] == "create"
                insert_attrs[version_column] = 1
              else
                # Get max version for this auditable
                max_version = audit_class.where({"#{auditable_column}_type" => auditable_type}.merge(identity_map))
                  .maximum(version_column) || 0
                insert_attrs[version_column] = max_version + 1
              end

              # Set user from RequestStore or config
              user_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :user)
              if user_column && !insert_attrs.key?(user_column)
                user = ActiveVersion::RequestStore.audited_user if defined?(ActiveVersion::RequestStore)
                user ||= begin
                  user_method = ActiveVersion.config.current_user_method
                  send(user_method) if respond_to?(user_method, true)
                end
                if user
                  insert_attrs[user_column] = user.respond_to?(:id) ? user.id : user
                  if user_column.to_s.end_with?("_id") && user.respond_to?(:class, true)
                    type_column = user_column.to_s.gsub("_id", "_type")
                    insert_attrs[type_column] = user.class.name if audit_class.column_names.include?(type_column.to_s)
                  end
                end
              end

              # Set request_uuid from RequestStore or generate
              uuid_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :request_uuid)
              if uuid_column && audit_class.column_names.include?(uuid_column.to_s) && !insert_attrs.key?(uuid_column)
                insert_attrs[uuid_column] = ActiveVersion::RequestStore.request_uuid if defined?(ActiveVersion::RequestStore)
                insert_attrs[uuid_column] ||= SecureRandom.uuid if insert_attrs[uuid_column].blank?
              end

              # Set remote_address from RequestStore
              address_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :remote_address)
              if address_column && audit_class.column_names.include?(address_column.to_s) && !insert_attrs.key?(address_column)
                insert_attrs[address_column] = ActiveVersion::RequestStore.remote_address if defined?(ActiveVersion::RequestStore)
              end

              insert_attrs[:created_at] ||= Time.current
              insert_attrs[:updated_at] ||= Time.current

              if batch_capture_active
                batch_state[:values] << insert_attrs
                ActiveVersion.store_set(:active_version_audit_batch_state, batch_state)
                return nil
              end

              begin
                audit_class.create!(insert_attrs)
                combine_audits_if_needed if attrs[:action] != "create"
                audits.reset
                nil
              rescue ActiveRecord::RecordNotUnique => e
                # Handle unique constraint violation (likely version conflict)
                # Retry once with recalculated version
                if e.message.include?("version") && attrs[:action] != "create"
                  # Recalculate version and retry
                  # Use class_name from options if provided (for dynamically created classes)
                  auditable_type_for_query = audited_options[:class_name] || self.class.name
                  if auditable_type_for_query.nil?
                    raise ConfigurationError, "Cannot determine class name for dynamically created class. Please specify class_name option in has_audits"
                  end
                  max_version = audit_class.where({"#{auditable_column}_type" => auditable_type_for_query}.merge(active_version_audit_identity_map))
                    .maximum(version_column) || 0
                  insert_attrs[version_column] = max_version + 1
                  begin
                    audit_class.create!(insert_attrs)
                    combine_audits_if_needed if attrs[:action] != "create"
                    audits.reset
                    nil
                  rescue => retry_error
                    handle_audit_errors(retry_error, attrs[:action])
                    nil
                  end
                else
                  handle_audit_errors(e, attrs[:action])
                  nil
                end
              rescue => e
                handle_audit_errors(e, attrs[:action])
                nil
              end
            end
          end
        end

        def handle_audit_errors(error, action)
          ActiveVersion::Instrumentation.instrument_audit_write_failed(self, error: error, action: action)
          behavior = audited_options[:error_behavior] || ActiveVersion.config.audit_error_behavior || :log

          case behavior
          when :log
            log_audit_errors(error, action)
          when :exception
            raise error
          when :silent
            # noop
          end
        end

        def log_audit_errors(error, action)
          Rails.logger&.warn(
            "Unable to create audit for #{action} of #{self.class.name}" \
            "##{id}: #{error.message}"
          )
        end

        def map_structured_audit_columns(insert_attrs, payload)
          return unless payload.is_a?(Hash)

          payload.each do |attr, value|
            column_name = attr.to_s
            next unless audit_class.column_names.include?(column_name)

            insert_attrs[column_name] = value.is_a?(Array) ? value.last : value
          end
        end

        # Ensure table-storage audits can carry source identity/partition columns
        # even when those attributes did not change in this event.
        def copy_shared_source_columns(insert_attrs)
          shared_columns = audit_class.column_names & self.class.column_names
          excluded = [
            "id", "created_at", "updated_at",
            ActiveVersion.column_mapper.column_for(self.class, :audits, :changes).to_s,
            ActiveVersion.column_mapper.column_for(self.class, :audits, :context).to_s,
            ActiveVersion.column_mapper.column_for(self.class, :audits, :version).to_s,
            ActiveVersion.column_mapper.column_for(self.class, :audits, :action).to_s
          ]
          shared_columns -= excluded

          shared_columns.each do |column_name|
            next if insert_attrs.key?(column_name)
            insert_attrs[column_name] = self[column_name] if has_attribute?(column_name)
          end
        end
      end
    end
  end
end
