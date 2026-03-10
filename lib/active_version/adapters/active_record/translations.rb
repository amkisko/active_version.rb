module ActiveVersion
  module Adapters
    module ActiveRecord
      module Translations
        extend ActiveSupport::Concern

        included do
          # Add has_translations method to ActiveRecord::Base
        end

        module ClassMethods
          # Declare that a model has translations
          def has_translations(options = {})
            include ActiveVersion::Translations::HasTranslations

            # Store options
            ActiveVersion.registry.register(self, :translations, options)

            # Register translation class
            translation_class_name = "#{name}Translation"
            if const_defined?(translation_class_name)
              translation_class = const_get(translation_class_name)
              if options[:table_name] && translation_class.respond_to?(:table_name=)
                translation_class.table_name = options[:table_name].to_s
              end
              ActiveVersion.registry.register_version_class(self, :translations, translation_class)
            end
          end
        end
      end
    end
  end
end

# Include translations adapter in ActiveRecord::Base
ActiveSupport.on_load(:active_record) do
  include ActiveVersion::Adapters::ActiveRecord::Translations
end

# If ActiveRecord::Base is already loaded, include immediately
if defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:include)
  unless ActiveRecord::Base.included_modules.include?(ActiveVersion::Adapters::ActiveRecord::Translations)
    ActiveSupport.on_load(:active_record) { include ActiveVersion::Adapters::ActiveRecord::Translations }
  end
end
