require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  config.active_storage.service = :local if config.respond_to?(:active_storage)
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.action_view.annotate_rendered_view_with_filenames = false
  config.assets.quiet = true if config.respond_to?(:assets)
  config.action_controller.raise_on_missing_callback_actions = true if config.action_controller.respond_to?(:raise_on_missing_callback_actions=)
end
