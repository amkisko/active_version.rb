module ActiveVersion
  module Adapters
    module ActiveRecord
      module Revisions
        extend ActiveSupport::Concern

        included do
          # Add has_revisions method to ActiveRecord::Base
        end

        module ClassMethods
          # Declare that a model has revisions
          def has_revisions(options = {})
            include ActiveVersion::Revisions::HasRevisions
            extend ActiveVersion::Revisions::SQLBuilder::ClassMethods

            # Delegate to the concern implementation so callbacks/options are
            # installed consistently for the DSL path.
            ActiveVersion::Revisions::HasRevisions::ClassMethods
              .instance_method(:has_revisions)
              .bind_call(self, options)

            # Register revision class
            revision_class_name = "#{name}Revision"
            if const_defined?(revision_class_name)
              revision_class = const_get(revision_class_name)
              if options[:table_name] && revision_class.respond_to?(:table_name=)
                revision_class.table_name = options[:table_name].to_s
              end
              ActiveVersion.registry.register_version_class(self, :revisions, revision_class)
            end
          end
        end
      end
    end
  end
end

# Include revisions adapter in ActiveRecord::Base
ActiveSupport.on_load(:active_record) do
  include ActiveVersion::Adapters::ActiveRecord::Revisions
end

# If ActiveRecord::Base is already loaded, include immediately
if defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:include)
  unless ActiveRecord::Base.include?(ActiveVersion::Adapters::ActiveRecord::Revisions)
    ActiveSupport.on_load(:active_record) { include ActiveVersion::Adapters::ActiveRecord::Revisions }
  end
end
