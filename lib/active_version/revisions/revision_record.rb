require "active_version/revisions/sql_builder"

module ActiveVersion
  module Revisions
    # Marker module for revision models
    # Identifies a model as a revision record
    module RevisionRecord
      extend ActiveSupport::Concern
      include SQLBuilder

      included do
        class_attribute :active_version_revision_schema, instance_writer: false, default: {}

        # Mark this as a revision record
        def self.revision_record?
          true
        end

        # Get source model name (e.g., "Post" from "PostRevision")
        def self.source_name
          return @source_name if @source_name
          return nil unless name
          @source_name = name.underscore.gsub("_revision", "").to_sym
        end

        # Get source model class (lazy)
        def self.source_class
          @source_class ||= begin
            klass = source_name.to_s.classify.safe_constantize
            klass || raise(NameError, "Could not find source class #{source_name.to_s.classify}")
          end
        end

        # Get foreign key name(s) (e.g., "post_id" or ["tenant_id", "post_id"])
        def self.source_foreign_key
          schema_foreign_key = (active_version_revision_schema || {})[:foreign_key]
          if schema_foreign_key.present?
            return schema_foreign_key.is_a?(Array) ? schema_foreign_key.map(&:to_s) : schema_foreign_key.to_s
          end

          model_name = source_name.to_s.classify
          options = ActiveVersion.registry.config_for_model_name(model_name, :revisions) || {}
          options = ActiveVersion.registry.config_for(source_class, :revisions) || {} if options.empty?
          foreign_key = options[:foreign_key].presence || "#{source_name}_id"
          foreign_key.is_a?(Array) ? foreign_key.map(&:to_s) : foreign_key.to_s
        rescue NameError
          "#{source_name}_id"
        end

        def self.source_primary_key
          schema_identity_resolver = (active_version_revision_schema || {})[:identity_resolver]
          if schema_identity_resolver.present?
            return schema_identity_resolver.map(&:to_s) if schema_identity_resolver.is_a?(Array)
            return schema_identity_resolver.to_s if schema_identity_resolver.is_a?(Symbol)
            return schema_identity_resolver if schema_identity_resolver.is_a?(String) && schema_identity_resolver.present?
          end

          model_name = source_name.to_s.classify
          options = ActiveVersion.registry.config_for_model_name(model_name, :revisions) || {}
          options = ActiveVersion.registry.config_for(source_class, :revisions) || {} if options.empty?

          resolver = options[:identity_resolver]
          return resolver.map(&:to_s) if resolver.is_a?(Array)
          return resolver.to_s if resolver.is_a?(Symbol)
          return resolver if resolver.is_a?(String) && resolver.present?

          nil
        rescue NameError
          nil
        end

        def self.revision_column_for(concept)
          schema = active_version_revision_schema || {}
          schema_key = :"#{concept}_column"
          return schema[schema_key].to_sym if schema[schema_key].present?

          case concept
          when :version
            ActiveVersion.config.revision_version_column
          end
        end

        # Set up belongs_to association (deferred until source class exists)
        def self.setup_associations(force: false)
          reflection = reflect_on_association(source_name)
          return if @associations_setup && !force && Array(reflection&.foreign_key).map(&:to_s) == Array(source_foreign_key).map(&:to_s)
          @associations_setup = true

          assoc_options = {
            foreign_key: source_foreign_key,
            inverse_of: :revisions,
            touch: true
          }
          primary_key = source_primary_key
          assoc_options[:primary_key] = primary_key if primary_key.present?
          send(:belongs_to, source_name, **assoc_options)

          # Validations
          begin
            version_column = revision_column_for(:version)
            unless column_names.include?(version_column.to_s)
              fallback_column = column_names.find { |name| name.end_with?("version") }
              version_column = fallback_column.to_sym if fallback_column
            end
            validates version_column, presence: true, uniqueness: {scope: Array(source_foreign_key)} if version_column
          rescue NameError, *ActiveVersion::Runtime.active_record_connection_errors
            # Source class not yet defined, will be set up later
          end
        end

        # Instrumentation
        after_create :instrument_revision_created

        # Readonly enforcement - revisions are readonly once persisted
        # Use a flag to allow callbacks to raise custom errors instead of ActiveRecord::ReadOnlyRecord.
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
        after_rollback :clear_rolled_back_revisions

        # Scopes
        scope :latest, -> {
          version_column = ActiveVersion.column_mapper.column_for(source_class, :revisions, :version)
          order(version_column => :desc).limit(1)
        }
        scope :oldest, -> {
          version_column = ActiveVersion.column_mapper.column_for(source_class, :revisions, :version)
          order(version_column => :asc).limit(1)
        }
        scope :at_version, ->(version) {
          version_column = ActiveVersion.column_mapper.column_for(source_class, :revisions, :version)
          where(version_column => version)
        }
        scope :ascending, -> {
          version_column = ActiveVersion.column_mapper.column_for(source_class, :revisions, :version)
          order(version_column => :asc)
        }
        scope :descending, -> {
          version_column = ActiveVersion.column_mapper.column_for(source_class, :revisions, :version)
          order(version_column => :desc)
        }

        # Setup associations when class is loaded (only if name is available)
        setup_associations if name
      end

      class RevisionSchemaDSL
        def initialize(klass)
          @klass = klass
        end

        def version_column(value)
          @klass.revision_version_column(value)
        end

        def foreign_key(value)
          @klass.revision_foreign_key(value)
        end

        def identity_resolver(value)
          @klass.revision_identity_resolver(value)
        end
      end

      class_methods do
        def configure_revision(**options, &block)
          apply_revision_configuration(**options)
          RevisionSchemaDSL.new(self).instance_eval(&block) if block_given?
          active_version_revision_schema
        end

        def revision_version_column(value = nil) = schema_option(:version_column, value, cast: :symbol)
        def revision_foreign_key(value = nil) = schema_option(:foreign_key, value, cast: :identity)
        def revision_identity_resolver(value = nil) = schema_option(:identity_resolver, value, cast: :resolver)

        def apply_revision_configuration(version_column: nil, foreign_key: nil, identity_resolver: nil)
          revision_version_column(version_column) if version_column
          revision_foreign_key(foreign_key) if foreign_key
          revision_identity_resolver(identity_resolver) if identity_resolver
          active_version_revision_schema
        end

        private

        def schema_option(key, value, cast:)
          schema = (active_version_revision_schema || {}).dup
          return schema[key] if value.nil?

          schema[key] = case cast
          when :symbol
            value.to_sym
          when :identity
            value.is_a?(Array) ? value.map(&:to_s) : value.to_s
          when :resolver
            if value.is_a?(Array)
              value.map(&:to_s)
            elsif value.is_a?(Symbol)
              value.to_s
            else
              value
            end
          else
            value
          end
          self.active_version_revision_schema = schema
          schema[key]
        end
      end

      # Get source record
      def source
        send(self.class.source_name)
      end

      def attributes
        attrs = super
        filter = instance_variable_get(:@active_version_attributes_filter)
        return attrs unless filter
        attrs.slice(*filter)
      end

      private

      def instrument_revision_created
        ActiveVersion::Instrumentation.instrument_revision_created(self, source)
      end

      def raise_readonly_error
        raise ActiveVersion::ReadonlyVersionError,
          "#{self.class.name} records are readonly once persisted"
      end

      def clear_rolled_back_revisions
        # Clear association cache if this revision was rolled back
        source&.revisions&.reset
      end
    end
  end
end
