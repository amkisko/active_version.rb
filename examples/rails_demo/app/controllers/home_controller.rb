class HomeController < ApplicationController
  def index
    @posts = Post.includes(:author, :assignee).order(created_at: :desc).limit(12)
    @issues = Issue.includes(:author, :assignee).order(created_at: :desc).limit(12)
    @pull_requests = PullRequest.includes(:author, :assignee).order(created_at: :desc).limit(12)
    render_component Views::Home::Index.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      posts: @posts,
      issues: @issues,
      pull_requests: @pull_requests
    )
  end
end
