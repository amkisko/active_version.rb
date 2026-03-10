require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "is valid with a name" do
    category = Category.new(name: "Technology")

    assert category.valid?
  end

  test "destroys dependent posts" do
    user = User.create!(name: "Demo User", email: "demo@example.com", password: "password")
    category = Category.create!(name: "Science")
    post = Post.create!(title: "Draft", category: category, author: user)

    assert_difference("Post.count", -1) do
      category.destroy!
    end

    assert_nil Post.find_by(id: post.id)
  end
end
