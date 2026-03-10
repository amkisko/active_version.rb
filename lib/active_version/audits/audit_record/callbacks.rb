module ActiveVersion
  module Audits
    module AuditRecord
      # Callback methods for setting audit attributes
      module Callbacks
        extend ActiveSupport::Concern

        private

        def set_version_number
          auditable_column = nil
          begin
            source_class = self.class.source_class
            version_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :version)
            auditable_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :auditable)
          rescue NameError
            version_column = ActiveVersion.config.audit_version_column
            auditable_column = ActiveVersion.config.audit_auditable_column
          end

          # Skip if version is already set (e.g., from audit_writer)
          # Version should always be a positive integer when set, so check if it's not nil
          return if !self[version_column].nil?

          type_column = auditable_column.to_s.end_with?("_type") ? auditable_column.to_s : "#{auditable_column}_type"
          identity_columns = source_identity_columns(auditable_column)

          if action == "create"
            self[version_column] = 1
          else
            auditable_type_value = self[type_column]
            return if auditable_type_value.nil? || identity_columns.any? { |column| self[column].nil? }

            scope = self.class.where(type_column => auditable_type_value)
            identity_columns.each do |column|
              scope = scope.where(column => self[column])
            end
            max_version = scope.maximum(version_column).to_i
            self[version_column] = max_version + 1
          end
        end

        def set_audit_user
          user_column = begin
            ActiveVersion.column_mapper.column_for(self.class.source_class, :audits, :user)
          rescue NameError
            ActiveVersion.config.audit_user_column
          end
          return unless user_column

          # Try to get user from RequestStore first (like audited)
          user = ActiveVersion::RequestStore.audited_user if defined?(ActiveVersion::RequestStore)
          user ||= begin
            user_method = ActiveVersion.config.current_user_method
            if respond_to?(user_method, true)
              send(user_method)
            end
          end

          if user
            self[user_column] = user.respond_to?(:id) ? user.id : user
            # Set polymorphic type if user is polymorphic
            if user_column.to_s.end_with?("_id") && user.respond_to?(:class)
              type_column = user_column.to_s.gsub("_id", "_type")
              self[type_column] = user.class.name if self.class.column_names.include?(type_column)
            end
          end
        end

        def set_request_uuid
          uuid_column = begin
            ActiveVersion.column_mapper.column_for(self.class.source_class, :audits, :request_uuid)
          rescue NameError
            ActiveVersion.config.audit_request_uuid_column
          end
          return unless uuid_column && self.class.column_names.include?(uuid_column.to_s)

          # Try RequestStore first, then generate UUID
          self[uuid_column] = ActiveVersion::RequestStore.request_uuid if defined?(ActiveVersion::RequestStore)
          self[uuid_column] ||= SecureRandom.uuid if self[uuid_column].blank?
        end

        def set_remote_address
          address_column = begin
            ActiveVersion.column_mapper.column_for(self.class.source_class, :audits, :remote_address)
          rescue NameError
            ActiveVersion.config.audit_remote_address_column
          end
          return unless address_column && self.class.column_names.include?(address_column.to_s)

          # Try RequestStore first
          if defined?(ActiveVersion::RequestStore)
            self[address_column] = ActiveVersion::RequestStore.remote_address
          end
        end

        def set_audited_context
          context_column = begin
            ActiveVersion.column_mapper.column_for(self.class.source_class, :audits, :context)
          rescue NameError
            ActiveVersion.config.audit_context_column
          end
          return unless context_column

          # Context should already be set during creation via write_audit
          # This callback ensures it's set if it wasn't set during creation
          return if self[context_column].present?

          # Fallback: use global context if no context was set
          global_context = ActiveVersion.context || {}
          self[context_column] = global_context if global_context.any?
        end

        def instrument_audit_created
          auditable_column = ActiveVersion.column_mapper.column_for(self.class.source_class, :audits, :auditable)
          auditable_record = nil

          if respond_to?(auditable_column)
            auditable_record = send(auditable_column)
          end

          # If association didn't return a record, try to load it directly
          unless auditable_record
            type_column = auditable_column.to_s.end_with?("_type") ? auditable_column.to_s : "#{auditable_column}_type"
            identity_columns = source_identity_columns(auditable_column)
            identity_map = source_identity_map_for_lookup(identity_columns, auditable_column)
            auditable_type_value = self[type_column]

            if identity_map.values.none?(&:nil?) && auditable_type_value
              # Handle dynamically created classes
              if auditable_type_value.nil?
                # Try superclass for dynamically created classes
                source_class = self.class.source_class
                auditable_type_value = source_class.superclass&.name if source_class.superclass
              end

              if auditable_type_value
                auditable_klass = auditable_type_value.constantize
                auditable_record = if identity_map.size > 1
                  auditable_klass.find_by(identity_map)
                else
                  auditable_klass.find_by(id: identity_map.values.first)
                end
              end
            end
          end

          ActiveVersion::Instrumentation.instrument_audit_created(self, auditable_record)
        rescue ::NameError, ::NoMethodError, ActiveRecord::RecordNotFound
          # Association not set up yet or record not found, still instrument with nil
          ActiveVersion::Instrumentation.instrument_audit_created(self, nil)
        end

        def source_identity_columns(auditable_column)
          configured = if self.class.respond_to?(:source_identity_columns)
            self.class.source_identity_columns
          end
          Array(configured.presence || "#{auditable_column}_id").map(&:to_s)
        end

        def source_identity_map_for_lookup(identity_columns, auditable_column)
          prefix = "#{auditable_column}_"

          identity_columns.index_with do |column|
            self[column]
          end.each_with_object({}) do |(column, value), acc|
            source_column = if column == "#{auditable_column}_id"
              "id"
            elsif column.start_with?(prefix)
              column.delete_prefix(prefix)
            else
              column
            end
            acc[source_column] = value
          end
        end
      end
    end
  end
end
