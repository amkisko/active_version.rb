module ActiveVersion
  module Adapters
    module ActiveRecord
      # Base adapter for ActiveRecord integration
      module Base
        extend ActiveSupport::Concern

        included do
          # This will be extended by specific versioning modules
        end

        # Instance method to get column names (delegates to class method)
        # This provides compatibility with ActiveRecord's class method as an instance method
        def column_names
          self.class.column_names
        end

        module ClassMethods
          # Check if model has versioning enabled
          def has_versioning?(version_type)
            ActiveVersion.registry.registered?(self, version_type)
          end

          # Get version class for this model
          def version_class_for(version_type)
            ActiveVersion.registry.version_class_for(self, version_type)
          end
        end
      end
    end
  end
end

# Include base adapter in ActiveRecord::Base
ActiveSupport.on_load(:active_record) do
  include ActiveVersion::Adapters::ActiveRecord::Base
end
