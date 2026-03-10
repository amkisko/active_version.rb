module ActiveVersion
  module Translations
    # Concern for models that have translations
    module HasTranslations
      extend ActiveSupport::Concern

      included do
        class_attribute :translation_options, instance_writer: false, default: {}

        def self.normalize_translation_options(options)
          {
            foreign_key: normalize_identity_columns(options[:foreign_key]),
            identity_resolver: options[:identity_resolver],
            table_name: options[:table_name]
          }.compact
        end

        def self.normalize_identity_columns(value)
          return nil if value.nil?
          return value.map(&:to_s) if value.is_a?(Array)

          value.to_s
        end

        def self.has_translations(options = {})
          self.translation_options = normalize_translation_options(options)
          ActiveVersion.registry.register(self, :translations, translation_options)
          @translation_associations_setup = false
          setup_translation_associations if respond_to?(:setup_translation_associations)
        end

        # Class methods
        def self.translation_record?
          false
        end

        # Get translation class name
        def self.translation_class
          @translation_class ||= begin
            class_name = "#{name}Translation"
            klass = class_name.safe_constantize || begin
              table_based_name = "#{table_name.to_s.classify}Translation"
              table_based_name.safe_constantize || raise(NameError, "Could not find translation class #{class_name}")
            end
            apply_translation_table_name!(klass)
            klass
          end
        end

        # Get translation class name as string
        def self.translation_class_name
          translation_class&.name.to_s.presence || "#{name}Translation"
        rescue NameError
          "#{name}Translation"
        end

        def self.apply_translation_table_name!(klass)
          options = ActiveVersion.registry.config_for(self, :translations) || {}
          custom_table_name = options[:table_name]
          return klass unless custom_table_name && klass.respond_to?(:table_name=)

          klass.table_name = custom_table_name.to_s
          klass
        end

        def self.register_translation_column_mappings_from_destination(translation_klass)
          return unless translation_klass.respond_to?(:locale_column_name)
          locale_column = translation_klass.locale_column_name
          return unless locale_column
          ActiveVersion.column_mapper.register(self, :translations, :locale, locale_column)
        end

        # Set up associations (deferred to avoid constantize errors during module inclusion)
        def self.setup_translation_associations
          return if @translation_associations_setup
          @translation_associations_setup = true

          begin
            inverse = nil
            begin
              inverse_name = name.underscore.to_sym
              translation_klass = translation_class
              register_translation_column_mappings_from_destination(translation_klass)
              translation_klass.setup_associations(force: true) if translation_klass.respond_to?(:setup_associations)
              if translation_klass.respond_to?(:source_name) && translation_klass.source_name == inverse_name
                inverse = inverse_name
              end
            rescue NameError
              inverse = nil
            end

            assoc_options = {
              class_name: translation_class_name,
              dependent: :destroy,
              autosave: true,
              inverse_of: inverse || false
            }
            assoc_options[:foreign_key] = translation_klass.source_foreign_key if translation_klass&.respond_to?(:source_foreign_key)
            resolver = translation_klass&.source_primary_key
            if resolver.is_a?(Array)
              assoc_options[:primary_key] = resolver.map(&:to_s)
            elsif resolver.is_a?(String) && resolver.present?
              assoc_options[:primary_key] = resolver
            end

            has_many :translations, **assoc_options

            # Nested attributes (must be after association is set up)
            accepts_nested_attributes_for(:translations,
              reject_if: :all_blank,
              allow_destroy: true)

          rescue NameError
            # Translation class not yet defined, will be set up later
          end
        end

        # Callbacks
        before_validation :copy_values_from_translation, if: :respond_to_copy_values?

        after_create :update_default_translation

        # Register with version registry
        ActiveVersion.registry.register(self, :translations, translation_options || {})

        # Call setup after class is fully loaded
        setup_translation_associations if name
      end

      module ClassMethods
        # Scope for translated attribute
        def scope_for_translated_attribute(attribute_name, value, locale: I18n.locale)
          foreign_key = if translation_class.respond_to?(:source_foreign_key)
            translation_class.source_foreign_key
          else
            "#{name.underscore}_id"
          end
          identity_columns = Array(foreign_key).map(&:to_s)
          scope = translation_class.where(locale: locale).where(attribute_name => value)

          if identity_columns.one?
            ids = scope.select(identity_columns.first)
            where(id: ids)
          else
            ids = scope.pluck(*identity_columns)
            where(primary_key => ids)
          end
        end

        # Auto-generate scopes for translated attributes
        def translated_scopes(*attribute_names)
          attribute_names.each do |attribute_name|
            define_singleton_method(:"for_translated_#{attribute_name}") do |value, locale: I18n.locale|
              scope_for_translated_attribute(attribute_name, value, locale: locale)
            end

            define_singleton_method(:"find_by_translated_#{attribute_name}") do |value, locale: I18n.locale|
              scope_for_translated_attribute(attribute_name, value, locale: locale)
                .first || find_by(attribute_name => value)
            end
          end
        end

        # Auto-generate copy methods for translated attributes
        def translated_copies(*attribute_names)
          define_method(:copy_values_from_translation) do
            attribute_names.each do |attribute_name|
              if respond_to?(:will_save_change_to_attribute?) && will_save_change_to_attribute?(attribute_name)
                next
              end
              if respond_to?(:attribute_changed?) && attribute_changed?(attribute_name)
                next
              end
              next if self[attribute_name].present?

              value = translate(attribute_name, locale: I18n.default_locale).presence
              value ||= translations.first&.send(attribute_name)
              self[attribute_name] = value if value.present?
            end
          end
        end
      end

      # Translate an attribute to a specific locale
      def translate(attr_name, locale: nil, presence_check: nil, fallback: true)
        locale ||= I18n.locale
        locale_column = ActiveVersion.column_mapper.column_for(self.class, :translations, :locale)
        # Ensure the column exists in the translation class, fallback to default if not
        translation_class = self.class.translation_class
        unless translation_class.column_names.include?(locale_column.to_s)
          locale_column = ActiveVersion.config.translation_locale_column
        end

        translation_records = if persisted?
          translation_class.where(active_version_translation_identity_map)
        else
          translations
        end

        # Find translation for requested locale
        translation = translation_records.find do |t|
          t.send(locale_column) == locale &&
            t.attr_present_for_locale?(locale, attr_name, presence_check)
        end

        return translation&.send(attr_name) if translation

        # Fallback chain
        if fallback
          # Try default locale
          translation = translation_records.find do |t|
            t.send(locale_column) == I18n.default_locale &&
              t.attr_present_for_locale?(I18n.default_locale, attr_name, presence_check)
          end
          if translation
            ActiveVersion::Instrumentation.instrument_translation_fallback_used(
              self,
              attr: attr_name,
              requested_locale: locale,
              resolved_locale: I18n.default_locale
            )
            return translation.send(attr_name)
          end

          # Try any translation
          translation = translation_records.first
          if translation
            ActiveVersion::Instrumentation.instrument_translation_fallback_used(
              self,
              attr: attr_name,
              requested_locale: locale,
              resolved_locale: translation.send(locale_column)
            )
            return translation.send(attr_name)
          end

          # Try source record
          if respond_to?(attr_name)
            ActiveVersion::Instrumentation.instrument_translation_fallback_used(
              self,
              attr: attr_name,
              requested_locale: locale,
              resolved_locale: :source
            )
            return send(attr_name)
          end
        end

        nil
      end

      # Get translation record for a locale
      def translation(locale: nil)
        locale ||= I18n.locale
        locale_column = ActiveVersion.column_mapper.column_for(self.class, :translations, :locale)
        # Ensure the column exists in the translation class, fallback to default if not
        translation_class = self.class.translation_class
        unless translation_class.column_names.include?(locale_column.to_s)
          locale_column = ActiveVersion.config.translation_locale_column
        end
        # First try in-memory association
        result = translations.find { |t| t.send(locale_column) == locale }
        return result if result

        # If not found in memory, query database (in case translation was just created)
        return nil unless persisted?
        translation_class.where(
          active_version_translation_identity_map.merge(locale_column => locale)
        ).first
      end

      # Update default translation after create
      def update_default_translation
        locale_column = ActiveVersion.column_mapper.column_for(self.class, :translations, :locale)
        # Ensure the column exists in the translation class
        translation_class = self.class.translation_class
        unless translation_class.column_names.include?(locale_column.to_s)
          # Fall back to default if custom column doesn't exist
          locale_column = ActiveVersion.config.translation_locale_column
        end
        translation = translation_class.find_or_initialize_by(
          active_version_translation_identity_map.merge(locale_column => I18n.default_locale)
        )
        return if translation.persisted?

        # Copy attributes from source to default translation
        translation.assign_attributes(
          attributes.slice(
            *translation.attributes.keys.excluding(
              "id",
              "created_at",
              "updated_at",
              "locale",
              locale_column.to_s,
              *Array(translation.class.source_foreign_key).map(&:to_s)
            )
          )
        )
        translation.save
        translations.reset
      end

      private

      public

      def active_version_translation_identity_map
        columns = translation_identity_columns
        values = active_version_translation_identity_values

        case values
        when Hash
          values.transform_keys(&:to_s).slice(*columns)
        when Array
          columns.zip(values).to_h
        else
          {columns.first => values}
        end
      end

      def active_version_translation_identity_values
        resolver = self.class.translation_options && self.class.translation_options[:identity_resolver]
        return default_translation_identity_values if resolver.nil?

        case resolver
        when Proc
          resolver.arity.zero? ? instance_exec(&resolver) : resolver.call(self)
        when Array
          resolver.map { |column| public_send(column) }
        else
          public_send(resolver)
        end
      end

      def translation_identity_columns
        Array(self.class.translation_class.source_foreign_key).map(&:to_s)
      end

      def default_translation_identity_values
        columns = translation_identity_columns
        return id if columns.one?

        Array(self.class.primary_key).map { |column| self[column] }
      end

      def respond_to_copy_values?
        respond_to?(:copy_values_from_translation, true)
      end
    end
  end
end
