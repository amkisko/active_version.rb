require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @category = Category.create!(name: "General")
  end

  test "index renders successfully" do
    get categories_path
    assert_response :success
  end

  test "show renders successfully" do
    get category_path(@category)
    assert_response :success
  end

  test "new renders successfully" do
    get new_category_path
    assert_response :success
  end

  test "create persists category with valid params" do
    assert_difference("Category.count", 1) do
      post categories_path, params: { category: { name: "Science" } }
    end

    assert_redirected_to category_path(Category.order(:id).last)
  end

  test "create returns unprocessable entity with invalid params" do
    post categories_path, params: { category: { name: "" } }

    assert_response :unprocessable_entity
  end

  test "edit renders successfully" do
    get edit_category_path(@category)
    assert_response :success
  end

  test "update modifies category with valid params" do
    patch category_path(@category), params: { category: { name: "Updated" } }

    assert_redirected_to category_path(@category)
    assert_equal "Updated", @category.reload.name
  end

  test "update returns unprocessable entity with invalid params" do
    patch category_path(@category), params: { category: { name: "" } }

    assert_response :unprocessable_entity
  end

  test "destroy removes category" do
    assert_difference("Category.count", -1) do
      delete category_path(@category)
    end

    assert_redirected_to categories_path
  end
end
