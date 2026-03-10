module ActiveVersion
  module Adapters
    module ActiveRecord
      module Audits
        extend ActiveSupport::Concern

        included do
          # Add has_audits method to ActiveRecord::Base
        end

        module ClassMethods
          # Declare that a model has audits
          def has_audits(options = {})
            include ActiveVersion::Audits::HasAudits unless included_modules.include?(ActiveVersion::Audits::HasAudits)

            # Call the HasAudits implementation once included
            ActiveVersion::Audits::HasAudits::ClassMethods.instance_method(:has_audits)
              .bind_call(self, options)
          end
        end
      end
    end
  end
end

# Include audits adapter in ActiveRecord::Base
ActiveSupport.on_load(:active_record) do
  include ActiveVersion::Adapters::ActiveRecord::Audits
end

# If ActiveRecord::Base is already loaded, include immediately
if defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:include)
  unless ActiveRecord::Base.included_modules.include?(ActiveVersion::Adapters::ActiveRecord::Audits)
    ActiveSupport.on_load(:active_record) { include ActiveVersion::Adapters::ActiveRecord::Audits }
  end
end
