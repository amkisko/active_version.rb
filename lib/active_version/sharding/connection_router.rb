module ActiveVersion
  module Sharding
    # No-op router. Connection routing is application-owned.
    class ConnectionRouter
      class << self
        def connection_for(model_class, version_type)
          :default
        end

        def adapter_for(model_class, version_type)
          ActiveVersion.adapter_for(model_class, version_type)
        end

        def with_connection(model_class, version_type, &block)
          ActiveVersion.with_connection(model_class, version_type, &block)
        end
      end
    end
  end
end
