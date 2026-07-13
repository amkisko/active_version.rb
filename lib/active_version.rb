require "logger"
require "active_support"
begin
  require "active_record"
rescue LoadError
  # ActiveRecord is optional at runtime.
end

require "active_version/version"
require "active_version/configuration"
require "active_version/column_mapper"
require "active_version/version_registry"
require "active_version/instrumentation"
require "active_version/runtime"

# Main entry point for ActiveVersion
module ActiveVersion
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class VersionNotFoundError < Error; end
  class ReadonlyVersionError < Error; end
  class FutureTimeError < Error; end
  class DeletedColumnError < Error; end

  extend ActiveSupport::Autoload

  autoload :Adapters
  autoload :Translations
  autoload :Revisions
  autoload :Audits
  autoload :Database
  autoload :Sharding
  autoload :Query
  autoload :Migrators
  autoload :Runtime

  # Load translations module
  require "active_version/translations"
  # Load revisions module
  require "active_version/revisions"
  # Load audits module
  require "active_version/audits"

  # Load ActiveRecord adapters (they use ActiveSupport.on_load, so safe to require)
  begin
    # Ensure base adapter is loaded first
    require "active_version/adapters/active_record/base"
    require "active_version/adapters/active_record/translations"
    require "active_version/adapters/active_record/revisions"
    require "active_version/adapters/active_record/audits"
  rescue LoadError
    # Adapters may not be available in all environments
  end

  begin
    require "active_version/adapters/sequel"
  rescue LoadError
    # Sequel adapter is optional at runtime.
  end

  # Global configuration
  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield config if block_given?
    config
  end

  # Convenience methods for accessing configuration
  def self.auditing_enabled
    config.auditing_enabled
  end

  def self.auditing_enabled=(value)
    config.auditing_enabled = value
  end

  # Runtime adapter access (ActiveRecord by default).
  def self.runtime_adapter
    Runtime.adapter
  end

  def self.runtime_adapter=(adapter)
    Runtime.adapter = adapter
  end

  def self.reset_runtime_adapter!
    Runtime.reset_adapter!
  end

  # Context management (like audited)
  class RequestStore < ActiveSupport::CurrentAttributes
    attribute :version_context
    attribute :audited_user
    attribute :request_uuid
    attribute :remote_address
  end

  def self.context
    # Merge persistent context with request-scoped context
    persistent = store_get(:active_version_persistent_context) || {}
    request_scoped = RequestStore.version_context || {}
    persistent.merge(request_scoped)
  end

  def self.context=(value)
    raise ConfigurationError, "context must be a hash" unless value.is_a?(Hash)
    RequestStore.version_context = value
  end

  # Transaction-aware context (uses PostgreSQL session variables)
  # Accepts either a hash as first argument or keyword arguments
  def self.with_context(context = nil, transactional: true, **kwargs, &block)
    raise ArgumentError, "with_context requires a block" unless block_given?

    # If context is nil but kwargs are provided, use kwargs as context
    # If context is provided, use it (and ignore kwargs)
    # If both are nil/empty, use empty hash
    context_hash = if context.nil? && kwargs.any?
      kwargs
    elsif context.is_a?(Hash)
      context
    elsif context.nil?
      {}
    else
      raise ArgumentError, "context must be a hash or keyword arguments"
    end

    if transactional_context_supported?
      # Use PostgreSQL session variables for transaction-aware context
      with_transactional_context(context_hash, &block)
    else
      # Fallback to thread-local context
      with_thread_local_context(context_hash, &block)
    end
  end

  # Persistent context (connection-level, persists across operations)
  def self.with_context!(context)
    raise ArgumentError, "context must be a hash" unless context.is_a?(Hash)

    if store_get(:active_version_in_block)
      raise Error, "with_context! cannot be called from within a with_context block"
    end

    store_set(:active_version_persistent_context, context)
    nil
  end

  # Clear persistent context
  def self.clear_context!
    store_delete(:active_version_persistent_context)
    store_set(:active_version_context_depth, 0)
    store_set(:active_version_in_block, false)
    nil
  end

  def self.store_get(key)
    if config.execution_scope == :thread
      Thread.current.thread_variable_get(key)
    elsif Fiber.current.respond_to?(:[])
      Fiber.current[key]
    else
      thread_current_for_fallback_store[key]
    end
  end

  def self.store_set(key, value)
    if config.execution_scope == :thread
      Thread.current.thread_variable_set(key, value)
    elsif Fiber.current.respond_to?(:[]=)
      Fiber.current[key] = value
    else
      thread_current_for_fallback_store[key] = value
    end
  end

  def self.store_delete(key)
    store_set(key, nil)
  end

  def self.store_keys
    if config.execution_scope == :thread
      Thread.current.thread_variables
    elsif thread_current_for_fallback_store.respond_to?(:keys)
      thread_current_for_fallback_store.keys
    else
      []
    end
  end

  def self.thread_current_for_fallback_store
    Thread.current
  end
  private_class_method :thread_current_for_fallback_store

  def self.clear_scoped_keys!(pattern)
    store_keys.grep(pattern).each { |key| store_delete(key) }
  end
  public_class_method :store_get, :store_set, :store_delete, :clear_scoped_keys!

  def self.enter_context_block!
    depth = store_get(:active_version_context_depth).to_i + 1
    store_set(:active_version_context_depth, depth)
    store_set(:active_version_in_block, depth.positive?)
  end

  def self.leave_context_block!
    depth = store_get(:active_version_context_depth).to_i - 1
    depth = 0 if depth.negative?
    store_set(:active_version_context_depth, depth)
    store_set(:active_version_in_block, depth.positive?)
  end

  def self.with_transactional_context(context, &block)
    connection = Runtime.adapter.base_connection
    old_context = self.context.dup
    old_block_context = store_get(:active_version_block_context)
    enter_context_block!

    # Set PostgreSQL session variable
    if connection.open_transactions.positive?
      encoded_context = connection.quote(ActiveSupport::JSON.encode(context))
      connection.execute("SET LOCAL active_version.context = #{encoded_context}")
    end

    # Also update thread-local for immediate access
    self.context = old_context.merge(context)
    store_set(:active_version_block_context, context)

    yield
  ensure
    # Context is automatically cleared on transaction rollback
    # But we still restore thread-local context
    self.context = old_context
    store_set(:active_version_block_context, old_block_context)
    leave_context_block!
  end

  def self.transactional_context_supported?
    connection = Runtime.adapter.base_connection
    Runtime.supports_transactional_context?(connection)
  rescue *Runtime.active_record_connection_errors
    false
  rescue
    false
  end

  def self.time_parser
    zone = Time.zone if Time.respond_to?(:zone)
    zone || Time
  end

  def self.with_thread_local_context(context, &block)
    old_context = self.context.dup
    old_block_context = store_get(:active_version_block_context)
    enter_context_block!
    self.context = old_context.merge(context)
    store_set(:active_version_block_context, context)
    yield
  ensure
    self.context = old_context
    store_set(:active_version_block_context, old_block_context)
    leave_context_block!
  end

  # Disable versioning globally
  def self.without_auditing
    auditing_was_enabled = auditing_enabled
    disable_auditing
    yield
  ensure
    enable_auditing if auditing_was_enabled
  end

  def self.disable_auditing
    self.auditing_enabled = false
  end

  def self.enable_auditing
    self.auditing_enabled = true
  end

  # Version registry access
  def self.registry
    @registry ||= VersionRegistry.new
  end

  # Column mapper access
  def self.column_mapper
    @column_mapper ||= ColumnMapper.new
  end

  # Parse time from various formats
  # Converts Numeric (Unix timestamp), String, Date, Time, or other objects to Time
  # @param time [Numeric, String, Date, Time, Object] Time value in various formats
  # @return [Time] Time object
  def self.parse_time(time)
    parser = time_parser
    case time
    when Numeric then parser.at(time)
    when String then parser.parse(time)
    when Date then time.to_time
    when Time then time
    else parser.parse(time.to_s)
    end
  end

  # Parse time and return Time object (alias for clarity)
  def self.parse_time_to_time(time)
    parse_time(time)
  end

  # Connection access is intentionally application-owned.
  # ActiveVersion does not route between shards/connections.
  # These methods remain as pass-through helpers.
  def self.connection_for(model_class, version_type)
    :default
  end

  def self.adapter_for(model_class, version_type)
    Runtime.adapter.connection_for(model_class, version_type)
  end

  def self.with_connection(model_class, version_type, &block)
    yield(Runtime.adapter.connection_for(model_class, version_type))
  end

  # Library warnings (defaults to stderr). Set to +nil+ to silence; use +Logger.new(File::NULL)+ in tests.
  class << self
    attr_writer :logger

    def logger
      return @logger if defined?(@logger)

      @logger = default_logger
    end

    def log_debug(message)
      logger = self.logger
      return if logger.nil?

      logger.debug(message) if logger.respond_to?(:debug)
    end

    def default_logger
      l = Logger.new($stderr)
      l.level = Logger::WARN
      l.formatter = proc { |_, _, _, msg| "#{msg}\n" }
      l
    end
    private :default_logger
  end
end

# Load Rails integration if available
if defined?(Rails)
  require "active_version/railtie"
end
