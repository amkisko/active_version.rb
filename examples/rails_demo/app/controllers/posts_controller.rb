
class PostsController < ApplicationController
  before_action :set_post, only: [:show, :edit, :update, :destroy, :translations, :update_translations, :revisions, :audits, :revert_to_version, :switch_to_version, :diff]

  def index
    @posts = Post.includes(:category, :author, :assignee).order(created_at: :desc)
    @posts = @posts.where("title LIKE ?", "%#{params[:search]}%") if params[:search].present?

    post_ids = @posts.map(&:id)
    if post_ids.empty?
      @translation_counts_by_post_id = {}
      @revision_counts_by_post_id = {}
      @audit_counts_by_post_id = {}
      @current_versions_by_post_id = {}
    else
      @translation_counts_by_post_id = PostTranslation.where(post_id: post_ids).group(:post_id).count
      @revision_counts_by_post_id = PostRevision.where(post_id: post_ids).group(:post_id).count
      @audit_counts_by_post_id = PostAudit.where(auditable_type: "Post", auditable_id: post_ids).group(:auditable_id).count
      @current_versions_by_post_id = PostRevision.where(post_id: post_ids).group(:post_id).maximum(:version)
    end

    @total_translations = @translation_counts_by_post_id.values.sum
    @total_revisions = @revision_counts_by_post_id.values.sum
    @total_audits = @audit_counts_by_post_id.values.sum

    render_component Views::Posts::Index.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      posts: @posts,
      total_translations: @total_translations,
      total_revisions: @total_revisions,
      total_audits: @total_audits
    )
  end

  def show
    @current_locale = params[:locale] || I18n.default_locale
    render_component Views::Posts::Show.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      post: @post,
      current_locale: @current_locale
    )
  end

  def new
    @post = Post.new
    @categories = Category.all
    @users = User.order(:name)
    render_component Views::Posts::Form.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      post: @post,
      categories: @categories,
      users: @users,
      action: :new
    )
  end

  def create
    @post = Post.new(post_params)
    @post.author = @current_user
    audit_comment = params.dig(:post, :audit_comment)
    @post.audit_comment = audit_comment if audit_comment.present?

    if @post.save
      redirect_to @post, notice: "Post was successfully created."
    else
      @categories = Category.all
      @users = User.order(:name)
      render_component Views::Posts::Form.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        post: @post,
        categories: @categories,
        users: @users,
        action: :new
      ), status: :unprocessable_entity
    end
  end

  def edit
    @categories = Category.all
    @users = User.order(:name)
    @current_locale = params[:locale] || I18n.default_locale
    render_component Views::Posts::Form.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      post: @post,
      categories: @categories,
      users: @users,
      action: :edit
    )
  end

  def update
    unless params[:post].present?
      redirect_to edit_post_path(@post), alert: "No form data submitted."
      return
    end

    audit_comment = params.dig(:post, :audit_comment)
    @post.audit_comment = audit_comment if audit_comment.present?

    if @post.update(post_params)
      redirect_to @post, notice: "Post was successfully updated."
    else
      @categories = Category.all
      @users = User.order(:name)
      render_component Views::Posts::Form.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        post: @post,
        categories: @categories,
        users: @users,
        action: :edit
      ), status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_url, notice: "Post was successfully destroyed."
  end

  def translations
    @current_locale = params[:locale] || I18n.default_locale
    @available_locales = I18n.available_locales
    render_component Views::Posts::Translations.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      post: @post,
      current_locale: @current_locale,
      available_locales: @available_locales
    )
  end

  def update_translations
    locale = params.dig(:post_translation, :locale).to_s.presence || params[:locale].to_s.presence
    unless locale && I18n.available_locales.map(&:to_s).include?(locale)
      redirect_to translations_post_path(@post), alert: "Invalid locale."
      return
    end

    translation = @post.translations.find_or_initialize_by(locale: locale)
    if translation.update(translation_params)
      redirect_to translations_post_path(@post, locale: locale), notice: "Translation for #{locale.upcase} was saved."
    else
      @current_locale = locale
      @available_locales = I18n.available_locales
      render_component Views::Posts::Translations.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        post: @post,
        current_locale: @current_locale,
        available_locales: @available_locales
      ), status: :unprocessable_entity
    end
  end

  def revisions
    @revisions = @post.revisions.order(version: :desc)
    render_component Views::Posts::Revisions.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      post: @post,
      revisions: @revisions
    )
  end

  def audits
    @audits = @post.audits.includes(:user).order(version: :desc)
    @audits = @audits.where(action: params[:action_filter]) if params[:action_filter].present?
    render_component Views::Posts::Audits.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      post: @post,
      audits: @audits
    )
  end

  def revert_to_version
    version = params[:version].to_i
    if @post.revert_to(version: version)
      redirect_to @post, notice: "Post reverted to version #{version}."
    else
      redirect_to revisions_post_path(@post), alert: "Failed to revert to version #{version}."
    end
  end

  def switch_to_version
    version = params[:version].to_i
    append = params[:append] == "true"
    if @post.switch_to!(version, append: append)
      redirect_to @post, notice: "Post switched to version #{version}."
    else
      redirect_to revisions_post_path(@post), alert: "Failed to switch to version #{version}."
    end
  end

  def diff
    @from_version = params[:from_version]&.to_i || 1
    @to_version = params[:to_version]&.to_i || @post.current_version
    begin
      @diff = @post.diff_from(version: @from_version)
      @diff = { "changes" => @diff } unless @diff.is_a?(Hash) && @diff.key?("changes")
    rescue => e
      @diff = { "changes" => {}, "error" => e.message }
    end
    render_component Views::Posts::Diff.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      post: @post,
      from_version: @from_version,
      to_version: @to_version,
      diff: @diff
    )
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(
      :title, :body, :category_id, :assignee_id, :attachment, :status, :price, :published_at, :seo_title, :keywords_csv, :labels_csv,
      translations_attributes: [:id, :locale, :title, :body, :attachment, :seo_title, :keywords_csv, :labels_csv, :_destroy]
    )
  end

  def translation_params
    params.require(:post_translation).permit(:locale, :title, :body, :attachment, :seo_title, :keywords_csv, :labels_csv)
  end
end
