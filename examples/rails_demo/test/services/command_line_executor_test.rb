require "test_helper"

class CommandLineExecutorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Cmd User", email: "cmd_user@example.com", password: "password")
    @category = Category.create!(name: "Cmd Category")
    @post = Post.create!(title: "Cmd Post", body: "Body", category: @category, author: @user)
    @executor = CommandLineExecutor.new(current_user: @user)
  end

  test "supports create post with natural language syntax" do
    result = @executor.execute("create post title='Hello from cmdk'")

    assert result[:ok]
    assert_equal "Post created", result[:title]
    assert_includes result[:lines].first, "Hello from cmdk"
  end

  test "supports dotted syntax create" do
    result = @executor.execute("post.create(title:'Dotted syntax')")

    assert result[:ok]
    assert_equal "Post created", result[:title]
    assert_includes result[:lines].first, "Dotted syntax"
  end

  test "supports post translations command" do
    @post.translations.create!(locale: "fi", title: "Moi", body: "Maailma")

    result = @executor.execute("post translations")

    assert result[:ok]
    assert_equal "All translations", result[:title]
    assert result[:lines].any? { |line| line.include?("locale=\"fi\"") }
  end

  test "returns error for unknown command" do
    result = @executor.execute("totally unknown command")

    assert_not result[:ok]
    assert_equal "Command Error", result[:title]
  end
end
