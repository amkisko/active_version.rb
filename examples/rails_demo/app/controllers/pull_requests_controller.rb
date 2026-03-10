class PullRequestsController < ApplicationController
  before_action :set_pull_request, only: [:show, :edit, :update, :destroy, :translations, :update_translations, :revisions, :audits, :revert_to_version, :switch_to_version]

  def index
    @pull_requests = PullRequest.includes(:author, :assignee).order(created_at: :desc)
    @pull_requests = @pull_requests.where("title LIKE ?", "%#{params[:search]}%") if params[:search].present?
    render_component Views::PullRequests::Index.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      pull_requests: @pull_requests
    )
  end

  def show
    @current_locale = params[:locale] || I18n.default_locale
    render_component Views::PullRequests::Show.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      pull_request: @pull_request,
      current_locale: @current_locale
    )
  end

  def new
    @pull_request = PullRequest.new(status: "open", source_branch: "feature", target_branch: "main")
    @users = User.order(:name)
    render_component Views::PullRequests::Form.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      pull_request: @pull_request,
      users: @users
    )
  end

  def create
    @pull_request = PullRequest.new(pull_request_params)
    @pull_request.author = @current_user
    @pull_request.audit_comment = params.dig(:pull_request, :audit_comment) if params.dig(:pull_request, :audit_comment).present?

    if @pull_request.save
      redirect_to @pull_request, notice: "Pull request was successfully created."
    else
      @users = User.order(:name)
      render_component Views::PullRequests::Form.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        pull_request: @pull_request,
        users: @users
      ), status: :unprocessable_entity
    end
  end

  def edit
    @users = User.order(:name)
    @current_locale = params[:locale] || I18n.default_locale
    render_component Views::PullRequests::Form.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      pull_request: @pull_request,
      users: @users
    )
  end

  def update
    @pull_request.audit_comment = params.dig(:pull_request, :audit_comment) if params.dig(:pull_request, :audit_comment).present?

    if @pull_request.update(pull_request_params)
      redirect_to @pull_request, notice: "Pull request was successfully updated."
    else
      @users = User.order(:name)
      render_component Views::PullRequests::Form.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        pull_request: @pull_request,
        users: @users
      ), status: :unprocessable_entity
    end
  end

  def destroy
    @pull_request.destroy
    redirect_to pull_requests_path, notice: "Pull request was successfully deleted."
  end

  def translations
    @current_locale = params[:locale] || I18n.default_locale
    @available_locales = I18n.available_locales
    render_component Views::PullRequests::Translations.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      pull_request: @pull_request,
      current_locale: @current_locale,
      available_locales: @available_locales
    )
  end

  def update_translations
    locale = params.dig(:pull_request_translation, :locale).to_s.presence || params[:locale].to_s.presence
    unless locale && I18n.available_locales.map(&:to_s).include?(locale)
      redirect_to translations_pull_request_path(@pull_request), alert: "Invalid locale."
      return
    end

    translation = @pull_request.translations.find_or_initialize_by(locale: locale)
    if translation.update(translation_params)
      redirect_to translations_pull_request_path(@pull_request, locale: locale), notice: "Translation for #{locale.upcase} was saved."
    else
      @current_locale = locale
      @available_locales = I18n.available_locales
      render_component Views::PullRequests::Translations.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        pull_request: @pull_request,
        current_locale: @current_locale,
        available_locales: @available_locales
      ), status: :unprocessable_entity
    end
  end

  def revisions
    @revisions = @pull_request.revisions.order(version: :desc)
    render_component Views::PullRequests::Revisions.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      pull_request: @pull_request,
      revisions: @revisions
    )
  end

  def audits
    @audits = @pull_request.audits.includes(:user).order(version: :desc)
    @audits = @audits.where(action: params[:action_filter]) if params[:action_filter].present?
    render_component Views::PullRequests::Audits.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      pull_request: @pull_request,
      audits: @audits
    )
  end

  def revert_to_version
    version = params[:version].to_i
    if @pull_request.revert_to(version: version)
      redirect_to @pull_request, notice: "Pull request reverted to version #{version}."
    else
      redirect_to revisions_pull_request_path(@pull_request), alert: "Failed to revert to version #{version}."
    end
  end

  def switch_to_version
    version = params[:version].to_i
    append = params[:append] == "true"

    if @pull_request.switch_to!(version, append: append)
      redirect_to @pull_request, notice: "Pull request switched to version #{version}."
    else
      redirect_to revisions_pull_request_path(@pull_request), alert: "Failed to switch to version #{version}."
    end
  end

  private

  def set_pull_request
    @pull_request = PullRequest.find(params[:id])
  end

  def pull_request_params
    params.require(:pull_request).permit(
      :title, :body, :status, :source_branch, :target_branch, :assignee_id, :attachment, :labels_csv,
      translations_attributes: [:id, :locale, :title, :body, :attachment, :labels_csv, :_destroy]
    )
  end

  def translation_params
    params.require(:pull_request_translation).permit(:locale, :title, :body, :attachment, :labels_csv)
  end
end
