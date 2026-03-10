class ColumnPostsController < ApplicationController
  before_action :set_column_post, only: [:show, :edit, :update]

  def index
    @column_posts = ColumnPost.order(created_at: :desc)
    post_ids = @column_posts.map(&:id)
    @audit_counts_by_post_id = if post_ids.empty?
      {}
    else
      ColumnPostAudit.where(auditable_type: "ColumnPost", auditable_id: post_ids).group(:auditable_id).count
    end
    render_component Views::ColumnPosts::Index.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      column_posts: @column_posts,
      audit_counts_by_post_id: @audit_counts_by_post_id
    )
  end

  def show
    @audits = @column_post.audits.order(version: :desc)
    @audits = @audits.where(title: params[:title_filter]) if params[:title_filter].present?
    @audits = @audits.where(published: params[:published_filter] == "true") if params[:published_filter].present?
    render_component Views::ColumnPosts::Show.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      column_post: @column_post,
      audits: @audits
    )
  end

  def edit
    render_component Views::ColumnPosts::Edit.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      column_post: @column_post
    )
  end

  def update
    audit_comment = params.dig(:column_post, :audit_comment)
    @column_post.audit_comment = audit_comment if audit_comment.present?

    if @column_post.update(column_post_params)
      redirect_to column_post_path(@column_post), notice: "ColumnPost updated."
    else
      render_component Views::ColumnPosts::Edit.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        column_post: @column_post
      ), status: :unprocessable_entity
    end
  end

  private

  def set_column_post
    @column_post = ColumnPost.find(params[:id])
  end

  def column_post_params
    params.require(:column_post).permit(:title, :body, :internal_notes, :published)
  end
end
