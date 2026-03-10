class CompositeDemoAuditsController < ApplicationController
  before_action :set_composite_demo_audit, only: [:show]

  def index
    @composite_demo_audits = CompositeDemoAudit.recent
    render_component Views::CompositeDemoAudits::Index.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      composite_demo_audits: @composite_demo_audits
    )
  end

  def show
    render_component Views::CompositeDemoAudits::Show.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      composite_demo_audit: @composite_demo_audit
    )
  end

  private

  def set_composite_demo_audit
    @composite_demo_audit = CompositeDemoAudit.find(CompositeDemoAudit.param_to_id(params[:id]))
  end
end
