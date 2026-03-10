class UsersController < ApplicationController
  before_action :set_user

  def show
    @authored_posts = @user.posts.order(created_at: :desc).limit(20)
    @authored_issues = @user.issues.order(created_at: :desc).limit(20)
    @authored_pull_requests = @user.pull_requests.order(created_at: :desc).limit(20)

    @assigned_posts = @user.assigned_posts.order(created_at: :desc).limit(20)
    @assigned_issues = @user.assigned_issues.order(created_at: :desc).limit(20)
    @assigned_pull_requests = @user.assigned_pull_requests.order(created_at: :desc).limit(20)

    @user_audits = Audit.where(user_type: "User", user_id: @user.id).order(created_at: :desc).limit(30)
    render_component Views::Users::Show.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      user: @user,
      authored_posts: @authored_posts,
      authored_issues: @authored_issues,
      authored_pull_requests: @authored_pull_requests,
      assigned_posts: @assigned_posts,
      assigned_issues: @assigned_issues,
      assigned_pull_requests: @assigned_pull_requests,
      user_audits: @user_audits
    )
  end

  def edit
    render_component Views::Users::Edit.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      user: @user
    )
  end

  def update
    if @user.update(user_params)
      redirect_to user_path(@user), notice: "Profile updated."
    else
      render_component Views::Users::Edit.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        user: @user
      ), status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    permitted = [:name, :email]
    if params.dig(:user, :password).present?
      permitted += [:password, :password_confirmation]
    end
    params.require(:user).permit(*permitted)
  end
end
