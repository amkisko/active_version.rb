module ActiveVersion
  module Runtime
    REQUIRED_ADAPTER_METHODS = %i[base_connection connection_for].freeze

    class NullAdapter
      def base_connection
        raise ActiveVersion::ConfigurationError, "No runtime adapter available"
      end

      def connection_for(model_class, _version_type)
        if model_class.respond_to?(:connection)
          model_class.connection
        else
          raise ActiveVersion::ConfigurationError,
            "#{model_class} does not expose .connection. Configure ActiveVersion.runtime_adapter for this backend."
        end
      end

      def supports_transactional_context?(connection)
        postgresql_connection?(connection)
      end

      def supports_current_transaction_id?(connection)
        postgresql_connection?(connection)
      end

      def supports_partition_catalog_checks?(connection)
        postgresql_connection?(connection)
      end

      private

      def postgresql_connection?(connection)
        connection.respond_to?(:adapter_name) &&
          connection.adapter_name.to_s.casecmp("postgresql").zero?
      end
    end

    class ActiveRecordAdapter
      def base_connection
        ::ActiveRecord::Base.connection
      end

      def connection_for(model_class, _version_type)
        model_class.connection
      end

      def supports_transactional_context?(connection)
        postgresql_connection?(connection)
      end

      def supports_current_transaction_id?(connection)
        postgresql_connection?(connection)
      end

      def supports_partition_catalog_checks?(connection)
        postgresql_connection?(connection)
      end

      private

      def postgresql_connection?(connection)
        connection.respond_to?(:adapter_name) &&
          connection.adapter_name.to_s.casecmp("postgresql").zero?
      end
    end

    class << self
      def required_adapter_methods
        REQUIRED_ADAPTER_METHODS.dup
      end

      def valid_adapter?(runtime_adapter)
        missing_adapter_methods(runtime_adapter).empty?
      end

      def adapter
        @adapter ||= default_adapter
      end

      def adapter=(runtime_adapter)
        candidate = runtime_adapter || default_adapter
        validate_adapter!(candidate)
        @adapter = candidate
      end

      def reset_adapter!
        @adapter = default_adapter
      end

      def active_record_connection_errors
        return [] unless defined?(::ActiveRecord)

        [
          ::ActiveRecord::ConnectionNotEstablished,
          ::ActiveRecord::NoDatabaseError,
          ::ActiveRecord::StatementInvalid,
          ::ActiveRecord::ConnectionNotDefined
        ]
      end

      def supports_transactional_context?(connection)
        return adapter.supports_transactional_context?(connection) if adapter.respond_to?(:supports_transactional_context?)

        postgresql_connection?(connection)
      end

      def supports_current_transaction_id?(connection)
        return adapter.supports_current_transaction_id?(connection) if adapter.respond_to?(:supports_current_transaction_id?)

        postgresql_connection?(connection)
      end

      def supports_partition_catalog_checks?(connection)
        return adapter.supports_partition_catalog_checks?(connection) if adapter.respond_to?(:supports_partition_catalog_checks?)

        postgresql_connection?(connection)
      end

      private

      def validate_adapter!(runtime_adapter)
        missing_methods = missing_adapter_methods(runtime_adapter)
        return if missing_methods.empty?

        raise ActiveVersion::ConfigurationError,
          "runtime_adapter must respond to #{REQUIRED_ADAPTER_METHODS.join(", ")}; missing: #{missing_methods.join(", ")}"
      end

      def missing_adapter_methods(runtime_adapter)
        REQUIRED_ADAPTER_METHODS.reject { |method_name| runtime_adapter.respond_to?(method_name) }
      end

      def postgresql_connection?(connection)
        connection.respond_to?(:adapter_name) &&
          connection.adapter_name.to_s.casecmp("postgresql").zero?
      end

      def default_adapter
        if defined?(::ActiveRecord::Base)
          ActiveRecordAdapter.new
        else
          NullAdapter.new
        end
      end
    end
  end
end
