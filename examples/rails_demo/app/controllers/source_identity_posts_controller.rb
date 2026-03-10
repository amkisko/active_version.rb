class SourceIdentityPostsController < ApplicationController
  before_action :set_source_identity_post, only: [:show]

  def index
    @source_identity_posts = SourceIdentityPost.recent
    render_component Views::SourceIdentityPosts::Index.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      source_identity_posts: @source_identity_posts
    )
  end

  def show
    @translations = @source_identity_post.translations.order(created_at: :desc)
    @revisions = @source_identity_post.revisions.order(version: :desc)
    @audits = @source_identity_post.audits.order(version: :desc)
    render_component Views::SourceIdentityPosts::Show.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      source_identity_post: @source_identity_post,
      translations: @translations,
      revisions: @revisions,
      audits: @audits
    )
  end

  private

  def set_source_identity_post
    @source_identity_post = SourceIdentityPost.find(params[:id])
  end
end
