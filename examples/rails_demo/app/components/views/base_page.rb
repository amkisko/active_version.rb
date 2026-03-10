module Views
  class BasePage < ApplicationComponent
    def initialize(current_user:, notice:, alert:)
      @current_user = current_user
      @notice = notice
      @alert = alert
    end

    private

  def with_layout(title: "ActiveVersion Demo", &block)
    render Layouts::DemoLayout.new(
      current_user: @current_user,
      notice: @notice,
      alert: @alert,
      title: title
    ), &block
  end
end
end
