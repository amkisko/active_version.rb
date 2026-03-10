
class ApplicationController < ActionController::Base
  helper_method :current_user
  before_action :normalize_admin_request_format
  before_action :set_current_user
  around_action :set_active_version_context

  def authenticate_admin_user!
    return true if demo_mode?
    return true if current_admin_user.present?

    head :unauthorized
    false
  end

  def current_admin_user
    @current_admin_user ||= begin
      admin_email = ENV.fetch("DEMO_ADMIN_EMAIL", "admin@example.com")

      if demo_mode?
        AdminUser.find_or_create_by!(email: admin_email) do |admin|
          admin.encrypted_password = ENV.fetch("DEMO_ADMIN_ENCRYPTED_PASSWORD", SecureRandom.hex(64))
        end
      else
        AdminUser.find_by(email: admin_email) || AdminUser.first
      end
    end
  end

  private

  def render_component(component, status: :ok)
    render html: component.call(context: { helpers: view_context }).html_safe, layout: false, status: status
  end

  def current_user
    @current_user
  end

  def normalize_admin_request_format
    return unless request.path.start_with?("/admin")

    requested_format = params[:format].to_s

    # ActiveAdmin pagination links can occasionally come through as /resource.1.
    # Treat that suffix as page number instead of MIME format.
    if requested_format.match?(/\A\d+\z/)
      params[:page] ||= requested_format
      params.delete(:format)
      request.format = :html
      return
    end

    return if requested_format.casecmp("json").zero?

    request.format = :html if requested_format.blank?
  end

  def set_current_user
    # In demo mode, auto-provision a local user for convenience.
    # Outside demo mode, never create users implicitly.
    @current_user ||= begin
      demo_email = ENV.fetch("DEMO_USER_EMAIL", "demo@example.com")

      if demo_mode?
        User.find_or_create_by!(email: demo_email) do |user|
          user.name = ENV.fetch("DEMO_USER_NAME", "Demo User")
          user.password = ENV.fetch("DEMO_USER_PASSWORD", SecureRandom.base58(24))
        end
      else
        User.find_by(email: demo_email) || User.first
      end
    end
  end

  def set_active_version_context
    ActiveVersion::RequestStore.audited_user = @current_user
    ActiveVersion::RequestStore.request_uuid = request.uuid
    ActiveVersion::RequestStore.remote_address = request.remote_ip

    ActiveVersion.with_context(
      controller: self.class.name,
      action: action_name,
      ip: request.remote_ip,
      user_agent: request.user_agent
    ) do
      yield
    end
  end

  def demo_mode?
    ENV["DEMO_MODE"] == "1" || Rails.env.development? || Rails.env.test?
  end
end
