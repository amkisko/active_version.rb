require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.eager_load = false
  config.cache_classes = true
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  config.action_dispatch.show_exceptions = false
  config.action_controller.allow_forgery_protection = false
  config.active_storage.service = :test if config.respond_to?(:active_storage)
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: "www.example.com" }
  config.active_support.deprecation = :stderr
end
