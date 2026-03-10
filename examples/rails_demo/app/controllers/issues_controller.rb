class IssuesController < ApplicationController
  before_action :set_issue, only: [:show, :edit, :update, :destroy, :translations, :update_translations, :revisions, :audits, :revert_to_version, :switch_to_version]

  def index
    @issues = Issue.includes(:author, :assignee).order(created_at: :desc)
    @issues = @issues.where("title LIKE ?", "%#{params[:search]}%") if params[:search].present?
    render_component Views::Issues::Index.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      issues: @issues
    )
  end

  def show
    @current_locale = params[:locale] || I18n.default_locale
    render_component Views::Issues::Show.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      issue: @issue,
      current_locale: @current_locale
    )
  end

  def new
    @issue = Issue.new(status: "open")
    @users = User.order(:name)
    render_component Views::Issues::Form.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      issue: @issue,
      users: @users
    )
  end

  def create
    @issue = Issue.new(issue_params)
    @issue.author = @current_user
    @issue.audit_comment = params.dig(:issue, :audit_comment) if params.dig(:issue, :audit_comment).present?

    if @issue.save
      redirect_to @issue, notice: "Issue was successfully created."
    else
      @users = User.order(:name)
      render_component Views::Issues::Form.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        issue: @issue,
        users: @users
      ), status: :unprocessable_entity
    end
  end

  def edit
    @users = User.order(:name)
    @current_locale = params[:locale] || I18n.default_locale
    render_component Views::Issues::Form.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      issue: @issue,
      users: @users
    )
  end

  def update
    @issue.audit_comment = params.dig(:issue, :audit_comment) if params.dig(:issue, :audit_comment).present?

    if @issue.update(issue_params)
      redirect_to @issue, notice: "Issue was successfully updated."
    else
      @users = User.order(:name)
      render_component Views::Issues::Form.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        issue: @issue,
        users: @users
      ), status: :unprocessable_entity
    end
  end

  def destroy
    @issue.destroy
    redirect_to issues_path, notice: "Issue was successfully deleted."
  end

  def translations
    @current_locale = params[:locale] || I18n.default_locale
    @available_locales = I18n.available_locales
    render_component Views::Issues::Translations.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      issue: @issue,
      current_locale: @current_locale,
      available_locales: @available_locales
    )
  end

  def update_translations
    locale = params.dig(:issue_translation, :locale).to_s.presence || params[:locale].to_s.presence
    unless locale && I18n.available_locales.map(&:to_s).include?(locale)
      redirect_to translations_issue_path(@issue), alert: "Invalid locale."
      return
    end

    translation = @issue.translations.find_or_initialize_by(locale: locale)
    if translation.update(translation_params)
      redirect_to translations_issue_path(@issue, locale: locale), notice: "Translation for #{locale.upcase} was saved."
    else
      @current_locale = locale
      @available_locales = I18n.available_locales
      render_component Views::Issues::Translations.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        issue: @issue,
        current_locale: @current_locale,
        available_locales: @available_locales
      ), status: :unprocessable_entity
    end
  end

  def revisions
    @revisions = @issue.revisions.order(version: :desc)
    render_component Views::Issues::Revisions.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      issue: @issue,
      revisions: @revisions
    )
  end

  def audits
    @audits = @issue.audits.includes(:user).order(version: :desc)
    @audits = @audits.where(action: params[:action_filter]) if params[:action_filter].present?
    render_component Views::Issues::Audits.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      issue: @issue,
      audits: @audits
    )
  end

  def revert_to_version
    version = params[:version].to_i
    if @issue.revert_to(version: version)
      redirect_to @issue, notice: "Issue reverted to version #{version}."
    else
      redirect_to revisions_issue_path(@issue), alert: "Failed to revert to version #{version}."
    end
  end

  def switch_to_version
    version = params[:version].to_i
    append = params[:append] == "true"

    if @issue.switch_to!(version, append: append)
      redirect_to @issue, notice: "Issue switched to version #{version}."
    else
      redirect_to revisions_issue_path(@issue), alert: "Failed to switch to version #{version}."
    end
  end

  private

  def set_issue
    @issue = Issue.find(params[:id])
  end

  def issue_params
    params.require(:issue).permit(
      :title, :body, :status, :assignee_id, :attachment, :labels_csv,
      translations_attributes: [:id, :locale, :title, :body, :attachment, :labels_csv, :_destroy]
    )
  end

  def translation_params
    params.require(:issue_translation).permit(:locale, :title, :body, :attachment, :labels_csv)
  end
end
