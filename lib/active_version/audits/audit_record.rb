require "securerandom"
require "active_version/audits/sql_builder"
require "active_version/audits/audit_record/callbacks"
require "active_version/audits/audit_record/serializers"

module ActiveVersion
  module Audits
    # Marker module for audit models
    # Identifies a model as an audit record
    module AuditRecord
      extend ActiveSupport::Concern
      include SQLBuilder
      include Callbacks

      class AuditSchemaDSL
        def initialize(audit_class)
          @audit_class = audit_class
        end

        def storage(value) = @audit_class.audit_storage(value)
        def action_column(value) = @audit_class.audit_action_column(value)
        def changes_column(value) = @audit_class.audit_changes_column(value)
        def context_column(value) = @audit_class.audit_context_column(value)
        def comment_column(value) = @audit_class.audit_comment_column(value)
        def version_column(value) = @audit_class.audit_version_column(value)
        def user_column(value) = @audit_class.audit_user_column(value)
        def auditable_column(value) = @audit_class.audit_auditable_column(value)
        def associated_column(value) = @audit_class.audit_associated_column(value)
        def remote_address_column(value) = @audit_class.audit_remote_address_column(value)
        def request_uuid_column(value) = @audit_class.audit_request_uuid_column(value)
      end

      included do
        class_attribute :active_version_audit_schema, instance_writer: false, default: {}

        # Mark this as an audit record
        def self.audit_record?
          true
        end

        # Attributes will be defined in setup_associations when connection is available
        # This ensures ActiveRecord recognizes them as database columns before loading records

        # Allow our audit column names even if they conflict with ActiveRecord methods
        # This is necessary because 'audited_changes' is a standard audit column name
        # but conflicts with ActiveRecord's internal methods
        def self.dangerous_attribute_method?(name)
          changes_column = audit_column_for(:changes).to_s
          context_column = audit_column_for(:context).to_s
          return false if name.to_s == changes_column || name.to_s == context_column
          super
        end

        define_method(:audited_changes) do
          value = read_attribute(self.class.audit_column_for(:changes))
          self.class.deserialize_audit_payload(value, column_name: self.class.audit_column_for(:changes))
        end

        define_method(:audited_changes=) do |value|
          column_name = self.class.audit_column_for(:changes)
          write_attribute(column_name, self.class.serialize_audit_payload(value, column_name: column_name))
        end

        define_method(:audited_context) do
          value = read_attribute(self.class.audit_column_for(:context))
          parsed = self.class.deserialize_audit_payload(value, column_name: self.class.audit_column_for(:context))
          # Return HashWithIndifferentAccess to support both symbol and string keys
          if parsed.is_a?(Hash)
            parsed.with_indifferent_access
          else
            parsed
          end
        end

        define_method(:audited_context=) do |value|
          column_name = self.class.audit_column_for(:context)
          write_attribute(column_name, self.class.serialize_audit_payload(value, column_name: column_name))
        end

        # Get source model name (e.g., "Post" from "PostAudit")
        def self.source_name
          return @source_name if @source_name
          return nil unless name
          @source_name = name.underscore.gsub("_audit", "").to_sym
        end

        # Get source model class (lazy)
        def self.source_class
          @source_class ||= begin
            klass = source_name.to_s.classify.safe_constantize
            klass || raise(NameError, "Could not find source class #{source_name.to_s.classify}")
          end
        end

        # Get identity columns (e.g., ["post_id"] or ["tenant_id", "external_id"])
        def self.source_identity_columns
          options = ActiveVersion.registry.config_for_model_name(source_name.to_s.classify, :audits) || {}
          configured = options[:identity_columns]
          return configured.map(&:to_s) if configured.is_a?(Array)
          return [configured.to_s] if configured.present?

          @source_identity_columns ||= begin
            auditable_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :auditable)
            if auditable_column.to_s.end_with?("_id")
              [auditable_column.to_s]
            else
              ["#{auditable_column}_id"]
            end
          end
        rescue NameError
          # Source class not yet defined, use default
          ["auditable_id"]
        end

        # Set up associations (deferred until source class exists)
        def self.setup_associations
          return if @associations_setup
          @associations_setup = true

          begin
            # Define dangerous attributes as database columns to avoid DangerousAttributeError.
            if connection_pool&.connected?
              changes_column = audit_column_for(:changes)
              context_column = audit_column_for(:context)
              attribute changes_column, :text unless attribute_names.include?(changes_column.to_s)
              attribute context_column, :text unless attribute_names.include?(context_column.to_s)
            end
          rescue *ActiveVersion::Runtime.active_record_connection_errors => e
            if defined?(Rails) && Rails.respond_to?(:logger)
              Rails.logger&.debug("[ActiveVersion] Deferred audit attribute setup for #{name}: #{e.class}: #{e.message}")
            end
          end

          begin
            # Set up polymorphic association only when conventional id/type columns exist.
            auditable_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :auditable)
            if column_names.include?("#{auditable_column}_id") && column_names.include?("#{auditable_column}_type")
              send(:belongs_to, auditable_column, polymorphic: true)
            end

            # Set up user association (if configured)
            user_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :user)
            if user_column
              send(:belongs_to, user_column.to_s.gsub("_id", "").to_sym, polymorphic: true, optional: true)
            end

            # Set up associated model (if configured)
            associated_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :associated)
            if associated_column
              send(:belongs_to, associated_column.to_s.gsub("_id", "").to_sym, polymorphic: true, optional: true)
            end
          rescue NameError
            # Source class not yet defined, will be set up later
          end
        end

        # Callbacks (defined in Callbacks module)
        before_create :set_version_number, :set_audit_user, :set_request_uuid, :set_remote_address, :set_audited_context
        after_create :instrument_audit_created

        # Readonly enforcement - audits are readonly once persisted
        # Use a flag to temporarily disable readonly? during update/destroy
        # so our callbacks can raise the custom error instead of ActiveRecord's ReadOnlyRecord
        attr_accessor :_allow_update_for_readonly_check

        def readonly?
          return false if _allow_update_for_readonly_check
          persisted?
        end

        before_update :raise_readonly_error, if: :persisted?
        before_destroy :raise_readonly_error, if: :persisted?

        # Override save methods to set flag before ActiveRecord checks readonly?
        def save(*args, **kwargs, &block)
          self._allow_update_for_readonly_check = true if persisted?
          if kwargs.empty? && args.length == 1 && args[0].is_a?(Hash)
            kwargs = args.pop
          end
          if kwargs.any?
            super(**kwargs, &block)
          else
            super(*args, &block)
          end
        ensure
          self._allow_update_for_readonly_check = false
        end

        def save!(*args, **kwargs, &block)
          self._allow_update_for_readonly_check = true if persisted?
          if kwargs.empty? && args.length == 1 && args[0].is_a?(Hash)
            kwargs = args.pop
          end
          if kwargs.any?
            super(**kwargs, &block)
          else
            super(*args, &block)
          end
        ensure
          self._allow_update_for_readonly_check = false
        end

        def destroy(*args, **kwargs, &block)
          self._allow_update_for_readonly_check = true if persisted?
          if kwargs.any?
            super(**kwargs, &block)
          else
            super(*args, &block)
          end
        ensure
          self._allow_update_for_readonly_check = false
        end

        # Rollback handling
        after_rollback :clear_rolled_back_audits

        # Scopes
        scope :ascending, -> {
          version_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :version)
          reorder(version_column => :asc)
        }
        scope :descending, -> {
          version_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :version)
          reorder(version_column => :desc)
        }
        scope :creates, -> { where(audit_column_for(:action) => "create") }
        scope :updates, -> { where(audit_column_for(:action) => "update") }
        scope :destroys, -> { where(audit_column_for(:action) => "destroy") }
        scope :up_until, ->(date_or_time) { where("created_at <= ?", date_or_time) }
        scope :from_version, ->(version) {
          version_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :version)
          where("#{version_column} >= ?", version)
        }
        scope :to_version, ->(version) {
          version_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :version)
          where("#{version_column} <= ?", version)
        }
        scope :auditable_finder, ->(auditable_identity, auditable_type, identity_columns = nil) {
          auditable_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :auditable)
          type_key = "#{auditable_column}_type"
          columns = Array(identity_columns.presence || "#{auditable_column}_id").map(&:to_s)
          identity_map = case auditable_identity
          when Hash
            auditable_identity.transform_keys(&:to_s).slice(*columns)
          when Array
            columns.zip(auditable_identity).to_h
          else
            {columns.first => auditable_identity}
          end
          where({type_key => auditable_type}.merge(identity_map))
        }

        # Serialization for audit payload columns
        def self.setup_serializers
          return if @serializers_setup
          @serializers_setup = true
          initialize_serializers
        end

        # Setup when class is loaded (only if name is available)
        # This ensures attributes are defined before records are loaded
        setup_associations if name
        setup_serializers if name
      end

      class_methods do
        def configure_audit(**options, &block)
          audit_storage(options[:storage]) if options[:storage]
          audit_action_column(options[:action_column]) if options[:action_column]
          audit_changes_column(options[:changes_column]) if options[:changes_column]
          audit_context_column(options[:context_column]) if options[:context_column]
          audit_comment_column(options[:comment_column]) if options[:comment_column]
          audit_version_column(options[:version_column]) if options[:version_column]
          audit_user_column(options[:user_column]) if options[:user_column]
          audit_auditable_column(options[:auditable_column]) if options[:auditable_column]
          audit_associated_column(options[:associated_column]) if options[:associated_column]
          audit_remote_address_column(options[:remote_address_column]) if options[:remote_address_column]
          audit_request_uuid_column(options[:request_uuid_column]) if options[:request_uuid_column]
          AuditSchemaDSL.new(self).instance_eval(&block) if block_given?
          active_version_audit_schema
        end

        def audit_storage(value = nil) = schema_option(:storage, value)
        def audit_action_column(value = nil) = schema_option(:action_column, value)
        def audit_changes_column(value = nil) = schema_option(:changes_column, value)
        def audit_context_column(value = nil) = schema_option(:context_column, value)
        def audit_comment_column(value = nil) = schema_option(:comment_column, value)
        def audit_version_column(value = nil) = schema_option(:version_column, value)
        def audit_user_column(value = nil) = schema_option(:user_column, value)
        def audit_auditable_column(value = nil) = schema_option(:auditable_column, value)
        def audit_associated_column(value = nil) = schema_option(:associated_column, value)
        def audit_remote_address_column(value = nil) = schema_option(:remote_address_column, value)
        def audit_request_uuid_column(value = nil) = schema_option(:request_uuid_column, value)

        def audit_storage_mode
          schema_value = (active_version_audit_schema || {})[:storage]
          return schema_value.to_sym if schema_value

          ActiveVersion.config.audit_storage&.to_sym
        end

        def register_storage_provider(name, provider = nil, &factory)
          register_audit_storage_provider(name, provider, &factory)
        end

        def register_audit_storage_provider(name, provider = nil, &factory)
          entry = factory || provider
          raise ArgumentError, "storage provider object or factory block is required" if entry.nil?

          storage_provider_registry[name.to_sym] = entry
        end

        def storage_provider_registry
          @storage_provider_registry ||= begin
            inherited = if superclass.respond_to?(:storage_provider_registry)
              superclass.storage_provider_registry
            end
            (inherited || default_storage_provider_registry).dup
          end
        end

        def storage_provider_for_column(column_name)
          storage_mode = audit_storage_mode&.to_sym
          entry = storage_provider_registry[storage_mode]
          raise ActiveVersion::ConfigurationError, "unknown audit storage mode: #{storage_mode.inspect}" unless entry

          provider = entry.respond_to?(:call) ? entry.call(self, column_name.to_s) : entry
          unless provider.respond_to?(:load) && provider.respond_to?(:dump)
            raise ActiveVersion::ConfigurationError, "storage provider for #{storage_mode.inspect} must respond to #load and #dump"
          end

          provider
        end

        def serializer_for_column(column_name)
          storage_provider_for_column(column_name)
        end

        def deserialize_audit_payload(value, column_name:)
          serializer_for_column(column_name).load(value)
        end

        def serialize_audit_payload(value, column_name:)
          serializer_for_column(column_name).dump(value)
        end

        def audit_column_for(concept)
          schema = active_version_audit_schema || {}
          schema_key = :"#{concept}_column"
          return schema[schema_key].to_sym if schema[schema_key].present?

          case concept
          when :action then ActiveVersion.config.audit_action_column
          when :changes then ActiveVersion.config.audit_changes_column
          when :context then ActiveVersion.config.audit_context_column
          when :comment then ActiveVersion.config.audit_comment_column
          when :version then ActiveVersion.config.audit_version_column
          when :user then ActiveVersion.config.audit_user_column
          when :auditable then ActiveVersion.config.audit_auditable_column
          when :associated then ActiveVersion.config.audit_associated_column
          when :remote_address then ActiveVersion.config.audit_remote_address_column
          when :request_uuid then ActiveVersion.config.audit_request_uuid_column
          end
        end

        def schema_option(key, value)
          schema = (active_version_audit_schema || {}).dup
          return schema[key] if value.nil?
          schema[key] = value.to_sym
          self.active_version_audit_schema = schema
          schema[key]
        end

        private

        def default_storage_provider_registry
          {
            json_column: ->(_audit_class, _column_name) { AuditRecord::Serializers::Json.new },
            yaml_column: ->(_audit_class, _column_name) { AuditRecord::Serializers::Yaml.new },
            mirror_columns: ->(_audit_class, _column_name) { AuditRecord::Serializers::Identity.new }
          }
        end
      end

      module ClassMethods
        # Track which models use this audit class
        def add_audited_class(audited_class)
          @audited_classes ||= {}
          @audited_classes[name] ||= Set.new
          @audited_classes[name] << audited_class
        end

        def audited_classes
          @audited_classes ||= {}
          @audited_classes[name] ||= Set.new
        end

        # Initialize serializers for ActiveRecord serialize API (< Rails 8).
        # Rails 8+ relies on accessor-level serialization methods above.
        def initialize_serializers
          changes_column = audit_column_for(:changes)
          context_column = audit_column_for(:context)
          changes_serializer = serializer_for_column(changes_column)
          context_serializer = serializer_for_column(context_column)

          if ActiveRecord::VERSION::MAJOR >= 8
            # No-op: ActiveRecord 8 removed serialize API; handled in accessors.
          elsif ActiveRecord::VERSION::MAJOR >= 7 && ActiveRecord::VERSION::MINOR >= 1
            serialize changes_column, coder: changes_serializer
            serialize context_column, coder: context_serializer
          else
            serialize changes_column, changes_serializer
            serialize context_column, context_serializer
          end
        end

        # Reconstruct attributes from audit history
        def reconstruct_attributes(audits)
          version_column = audits.first.class.audit_column_for(:version) if audits.any? && audits.first.class.respond_to?(:audit_column_for)
          audits.each_with_object({}) do |audit, all|
            all.merge!(audit.new_attributes)
            all[:audit_version] = audit[version_column || :version]
          end
        end
      end

      # Get new attributes from this audit
      def new_attributes
        changes_column = self.class.audit_column_for(:changes)
        changes = send(changes_column) || {}
        if changes.is_a?(Hash) && changes.any?
          changes.each_with_object({}) do |(attr, values), attrs|
            attrs[attr] = (action_value == "update") ? values.last : values
          end
        else
          structured_audited_attributes
        end
      end

      def structured_audited_attributes
        source_columns = self.class.source_class.column_names
        ignored = ActiveVersion.config.ignored_attributes.map(&:to_s)

        source_columns.each_with_object({}) do |attr, attrs|
          next if ignored.include?(attr)
          next unless self.class.column_names.include?(attr)

          attrs[attr] = self[attr]
        end
      end

      # Get old attributes from this audit
      def old_attributes
        changes_column = self.class.audit_column_for(:changes)
        changes = send(changes_column) || {}
        return {} unless changes.is_a?(Hash) && changes.any?

        changes.each_with_object({}) do |(attr, values), attrs|
          attrs[attr] = (action_value == "update") ? values.first : nil
        end
      end

      # Get ancestors (all audits before this one)
      def ancestors
        auditable_column = ActiveVersion.column_mapper.column_for(self.class.source_class, :audits, :auditable)
        type_column = auditable_column.to_s.end_with?("_type") ? auditable_column.to_s : "#{auditable_column}_type"
        identity_columns = self.class.source_identity_columns
        auditable_identity_map = identity_columns.index_with { |column| self[column] }
        auditable_type_value = self[type_column]
        version_column = ActiveVersion.column_mapper.column_for(self.class.source_class, :audits, :version)
        version_value = self[version_column]
        self.class
          .ascending
          .auditable_finder(auditable_identity_map, auditable_type_value, identity_columns)
          .to_version(version_value)
      rescue ::NameError, ::NoMethodError
        self.class.none
      end

      # Reconstruct object at this revision
      def revision
        auditable_column = ActiveVersion.column_mapper.column_for(self.class.source_class, :audits, :auditable)
        auditable_record = send(auditable_column) if respond_to?(auditable_column)
        return nil unless auditable_record

        audits = ancestors
        attributes = self.class.reconstruct_attributes(audits)
        auditable_record.dup.tap do |revision|
          revision.assign_attributes(attributes)
          revision.instance_variable_set(:@new_record, destroyed?)
          revision.instance_variable_set(:@persisted, !destroyed?)
        end
      rescue ::NameError, ::NoMethodError
        nil
      end

      private

      def raise_readonly_error
        raise ActiveVersion::ReadonlyVersionError,
          "#{self.class.name} records are readonly once persisted"
      end

      def clear_rolled_back_audits
        # Clear association cache if this audit was rolled back

        auditable_column = ActiveVersion.column_mapper.column_for(self.class.source_class, :audits, :auditable)
        auditable_record = send(auditable_column) if respond_to?(auditable_column)
        auditable_record&.audits&.reset
      rescue ::NameError, ::NoMethodError
        # Association not set up yet or auditable doesn't have audits association
        # This is fine - just skip clearing the cache
      end

      private

      def action_value
        self[self.class.audit_column_for(:action)]
      end
    end
  end
end
