module ActiveVersion
  module Translations
    # Marker module for translation models
    # Identifies a model as a translation record
    module TranslationRecord
      extend ActiveSupport::Concern

      included do
        class_attribute :active_version_translation_schema, instance_writer: false, default: {}

        # Mark this as a translation record
        def self.translation_record?
          true
        end

        # Get source model name (e.g., "Post" from "PostTranslation")
        def self.source_name
          return @source_name if @source_name
          return nil unless name
          @source_name = name.underscore.gsub("_translation", "").to_sym
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
          schema_foreign_key = (active_version_translation_schema || {})[:foreign_key]
          if schema_foreign_key.present?
            return schema_foreign_key.is_a?(Array) ? schema_foreign_key.map(&:to_s) : schema_foreign_key.to_s
          end

          model_name = source_name.to_s.classify
          options = ActiveVersion.registry.config_for_model_name(model_name, :translations) || {}
          options = ActiveVersion.registry.config_for(source_class, :translations) || {} if options.empty?
          foreign_key = options[:foreign_key].presence || "#{source_name}_id"
          foreign_key.is_a?(Array) ? foreign_key.map(&:to_s) : foreign_key.to_s
        rescue NameError
          "#{source_name}_id"
        end

        def self.source_primary_key
          schema_identity_resolver = (active_version_translation_schema || {})[:identity_resolver]
          if schema_identity_resolver.present?
            return schema_identity_resolver.map(&:to_s) if schema_identity_resolver.is_a?(Array)
            return schema_identity_resolver.to_s if schema_identity_resolver.is_a?(Symbol)
            return schema_identity_resolver if schema_identity_resolver.is_a?(String) && schema_identity_resolver.present?
          end

          model_name = source_name.to_s.classify
          options = ActiveVersion.registry.config_for_model_name(model_name, :translations) || {}
          options = ActiveVersion.registry.config_for(source_class, :translations) || {} if options.empty?

          resolver = options[:identity_resolver]
          return resolver.map(&:to_s) if resolver.is_a?(Array)
          return resolver.to_s if resolver.is_a?(Symbol)
          return resolver if resolver.is_a?(String) && resolver.present?

          nil
        rescue NameError
          nil
        end

        def self.locale_column_name
          schema_locale = (active_version_translation_schema || {})[:locale_column]
          if schema_locale.present?
            return schema_locale.to_sym
          end

          locale_column = ActiveVersion.column_mapper.column_for(source_class, :translations, :locale)
          return locale_column if column_names.include?(locale_column.to_s)

          ActiveVersion.config.translation_locale_column
        rescue NameError, *ActiveVersion::Runtime.active_record_connection_errors
          ActiveVersion.config.translation_locale_column
        end

        # Set up belongs_to association (deferred until source class exists)
        def self.setup_associations(force: false)
          reflection = reflect_on_association(source_name)
          return if @associations_setup && !force && Array(reflection&.foreign_key).map(&:to_s) == Array(source_foreign_key).map(&:to_s)
          @associations_setup = true

          assoc_options = {
            foreign_key: source_foreign_key,
            inverse_of: :translations,
            touch: true
          }
          primary_key = source_primary_key
          assoc_options[:primary_key] = primary_key if primary_key.present?
          send(:belongs_to, source_name, **assoc_options)

          # Validations
          begin
            locale_column = locale_column_name
            validates locale_column, presence: true, uniqueness: {scope: Array(source_foreign_key)}
          rescue NameError, *ActiveVersion::Runtime.active_record_connection_errors
            # Source class not yet defined, will be set up later
          end
        end

        # Setup will be called when source class is available
        def self.setup_locale_enum
          return if @locale_enum_setup
          return unless defined?(I18n) && I18n.respond_to?(:available_locales)
          return unless source_name

          @locale_enum_setup = true
          begin
            locale_column = locale_column_name
            column = columns_hash[locale_column.to_s]
            return unless column&.type == :integer
            enum locale_column, I18n.available_locales.index_by(&:to_s)
          rescue NameError, *ActiveVersion::Runtime.active_record_connection_errors
            # Source class not yet defined
          end
        end

        # Scopes
        scope :for_locale, ->(locale) {
          return none unless source_name
          locale_column = locale_column_name
          where(locale_column => locale)
        }

        # After create hook to update source version
        after_create :update_source_version
        after_create :instrument_translation_created

        # After update hook to instrument translation updated
        after_update :instrument_translation_updated
        after_destroy :instrument_translation_destroyed

        # Setup associations when class is loaded (only if name is available)
        setup_associations if name
        setup_locale_enum if name
      end

      class TranslationSchemaDSL
        def initialize(klass)
          @klass = klass
        end

        def locale_column(value)
          @klass.translation_locale_column(value)
        end

        def foreign_key(value)
          @klass.translation_foreign_key(value)
        end

        def identity_resolver(value)
          @klass.translation_identity_resolver(value)
        end
      end

      class_methods do
        def configure_translation(**options, &block)
          apply_translation_configuration(**options)
          TranslationSchemaDSL.new(self).instance_eval(&block) if block_given?
          active_version_translation_schema
        end

        def translation_locale_column(value = nil) = schema_option(:locale_column, value, cast: :symbol)
        def translation_foreign_key(value = nil) = schema_option(:foreign_key, value, cast: :identity)
        def translation_identity_resolver(value = nil) = schema_option(:identity_resolver, value, cast: :resolver)

        def apply_translation_configuration(locale_column: nil, foreign_key: nil, identity_resolver: nil)
          translation_locale_column(locale_column) if locale_column
          translation_foreign_key(foreign_key) if foreign_key
          translation_identity_resolver(identity_resolver) if identity_resolver
          active_version_translation_schema
        end

        private

        def schema_option(key, value, cast:)
          schema = (active_version_translation_schema || {}).dup
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
          self.active_version_translation_schema = schema
          schema[key]
        end
      end

      # Check if attribute is present for locale
      def attr_present_for_locale?(locale, attr_name, presence_check = nil)
        return false unless self.class.source_name

        begin
          locale_column = self.class.locale_column_name
          return false unless send(locale_column).to_s == locale.to_s

          if presence_check
            send(presence_check, attr_name)
          else
            send(attr_name).present?
          end
        rescue NameError
          # Source class not yet defined, check locale directly
          return false unless respond_to?(:locale)
          return false unless self.locale.to_s == locale.to_s
          send(attr_name).present?
        end
      end

      # Get source version (for versioning of versions)
      def source_version
        send(self.class.source_name)
      end

      private

      def update_source_version
        source = send(self.class.source_name)
        return unless source

        # Update source's updated_at if it has translations
        if source.respond_to?(:update_default_translation)
          source.update_default_translation
        end
      end

      def instrument_translation_created
        ActiveVersion::Instrumentation.instrument_translation_created(self, source_version)
      end

      def instrument_translation_updated
        ActiveVersion::Instrumentation.instrument_translation_updated(self, source_version)
      end

      def instrument_translation_destroyed
        ActiveVersion::Instrumentation.instrument_translation_destroyed(self, source_version)
      end
    end
  end
end
