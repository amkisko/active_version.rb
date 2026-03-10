
class CategoriesController < ApplicationController
  before_action :set_category, only: [:show, :edit, :update, :destroy]

  def index
    @categories = Category.order(:name)
    category_ids = @categories.map(&:id)
    if category_ids.empty?
      @posts_count_by_category_id = {}
      @audits_count_by_category_id = {}
    else
      @posts_count_by_category_id = Post.where(category_id: category_ids).group(:category_id).count
      @audits_count_by_category_id = Audit.where(auditable_type: "Category", auditable_id: category_ids).group(:auditable_id).count
    end
    render_component Views::Categories::Index.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      categories: @categories,
      posts_count_by_category_id: @posts_count_by_category_id,
      audits_count_by_category_id: @audits_count_by_category_id
    )
  end

  def show
    @posts = @category.posts.includes(:author).order(created_at: :desc)
    render_component Views::Categories::Show.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      category: @category,
      posts: @posts
    )
  end

  def new
    @category = Category.new
    render_component Views::Categories::Form.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      category: @category
    )
  end

  def create
    @category = Category.new(category_params)

    if @category.save
      redirect_to @category, notice: "Category was successfully created."
    else
      render_component Views::Categories::Form.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        category: @category
      ), status: :unprocessable_entity
    end
  end

  def edit
    render_component Views::Categories::Form.new(
      current_user: @current_user,
      notice: flash[:notice],
      alert: flash[:alert],
      category: @category
    )
  end

  def update
    if @category.update(category_params)
      redirect_to @category, notice: "Category was successfully updated."
    else
      render_component Views::Categories::Form.new(
        current_user: @current_user,
        notice: flash[:notice],
        alert: flash[:alert],
        category: @category
      ), status: :unprocessable_entity
    end
  end

  def destroy
    @category.destroy
    redirect_to categories_url, notice: "Category was successfully destroyed."
  end

  private

  def set_category
    @category = Category.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name)
  end
end
