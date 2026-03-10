ActiveAdmin.setup do |config|
  config.site_title = "ActiveVersion Demo" if config.respond_to?(:site_title=)
  config.default_namespace = :admin if config.respond_to?(:default_namespace=)
  config.authentication_method = :authenticate_admin_user! if config.respond_to?(:authentication_method=)
  config.current_user_method = :current_admin_user if config.respond_to?(:current_user_method=)
  config.logout_link_path = false if config.respond_to?(:logout_link_path=)
  config.batch_actions = true if config.respond_to?(:batch_actions=)
  config.filter_attributes = [:encrypted_password, :password, :password_confirmation] if config.respond_to?(:filter_attributes=)
  config.localize_format = :long if config.respond_to?(:localize_format=)
  config.comments = false if config.respond_to?(:comments=)
  config.breadcrumb = true if config.respond_to?(:breadcrumb=)
  config.load_paths = [File.join(Rails.root, "app", "admin")] if config.respond_to?(:load_paths=)

  if config.respond_to?(:namespace)
    config.namespace :admin do |admin|
      admin.download_links = false if admin.respond_to?(:download_links=)
    end
  end

  config.on_unauthorized_access = proc do |controller, exception|
    message = exception.message
    if controller.request.format.html?
      controller.redirect_back fallback_location: controller.active_admin_root, alert: message
    else
      controller.render plain: message, status: :unauthorized
    end
  end
end
