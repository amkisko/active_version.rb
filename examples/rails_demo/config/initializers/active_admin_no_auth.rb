# Demo mode: allow all admin actions and formats without authorization checks.
Rails.application.config.to_prepare do
  if defined?(ActiveAdmin::ResourceController)
    ActiveAdmin::ResourceController.skip_before_action(:restrict_download_format_access!, raise: false)
  end
end
