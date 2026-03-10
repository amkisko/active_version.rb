require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.eager_load = true
  config.consider_all_requests_local = false
  config.require_master_key = false
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.log_tags = [:request_id]
  config.cache_store = :memory_store
  config.active_storage.service = :local if config.respond_to?(:active_storage)
  config.action_mailer.perform_caching = false
  config.active_support.report_deprecations = false if config.active_support.respond_to?(:report_deprecations=)
end
