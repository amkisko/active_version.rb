require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Author", email: "author@example.com", password: "password")
    @category = Category.create!(name: "Tech")
    @post = Post.create!(title: "Original Title", body: "Body", category: @category, author: @user)
  end

  test "root route renders index" do
    get root_path
    assert_response :success
  end

  test "index renders successfully and supports search" do
    get posts_path
    assert_response :success

    get posts_path, params: { search: "Original" }
    assert_response :success
  end

  test "show renders successfully with locale param" do
    get post_path(@post), params: { locale: "fi" }
    assert_response :success
  end

  test "new renders successfully" do
    get new_post_path
    assert_response :success
  end

  test "create persists post with valid params" do
    assert_difference("Post.count", 1) do
      post posts_path, params: {
        post: {
          title: "Created",
          body: "Created body",
          category_id: @category.id
        }
      }
    end

    created = Post.order(:id).last
    assert_redirected_to post_path(created)
    assert_not_nil created.author
  end

  test "create returns unprocessable entity with invalid params" do
    post posts_path, params: { post: { title: "", body: "Body", category_id: @category.id } }

    assert_response :unprocessable_entity
  end

  test "edit renders successfully" do
    get edit_post_path(@post), params: { locale: "sv" }
    assert_response :success
  end

  test "update modifies post with valid params" do
    patch post_path(@post), params: { post: { title: "Updated", body: "Updated body", audit_comment: "test change" } }

    assert_redirected_to post_path(@post)
    assert_equal "Updated", @post.reload.title
  end

  test "update returns unprocessable entity with invalid params" do
    patch post_path(@post), params: { post: { title: "" } }

    assert_response :unprocessable_entity
  end

  test "translations renders successfully" do
    get translations_post_path(@post), params: { locale: "en" }
    assert_response :success
  end

  test "revisions renders successfully" do
    get revisions_post_path(@post)
    assert_response :success
  end

  test "audits renders successfully and supports filter" do
    @post.update!(title: "Second Title")

    get audits_post_path(@post)
    assert_response :success

    get audits_post_path(@post), params: { action_filter: "update" }
    assert_response :success
  end

  test "revert_to_version redirects to post when successful" do
    @post.define_singleton_method(:revert_to) { |version:| version == 1 }

    Post.stubs(:find).returns(@post)
    post revert_to_version_post_path(@post), params: { version: 1 }

    assert_redirected_to post_path(@post)
  end

  test "revert_to_version redirects to revisions when failing" do
    @post.define_singleton_method(:revert_to) { |version:| version == 999 }

    Post.stubs(:find).returns(@post)
    post revert_to_version_post_path(@post), params: { version: 1 }

    assert_redirected_to revisions_post_path(@post)
  end

  test "switch_to_version redirects to post when successful" do
    @post.define_singleton_method(:switch_to!) { |version, append: false| version == 1 && append }

    Post.stubs(:find).returns(@post)
    post switch_to_version_post_path(@post), params: { version: 1, append: "true" }

    assert_redirected_to post_path(@post)
  end

  test "switch_to_version redirects to revisions when failing" do
    @post.define_singleton_method(:switch_to!) { |version, append: false| version == 999 && append }

    Post.stubs(:find).returns(@post)
    post switch_to_version_post_path(@post), params: { version: 1, append: "false" }

    assert_redirected_to revisions_post_path(@post)
  end

  test "diff renders with wrapped change payload when non-hash response is returned" do
    @post.define_singleton_method(:diff_from) { |version:| ["version #{version}"] }

    Post.stubs(:find).returns(@post)
    get diff_post_path(@post), params: { from_version: 1, to_version: 2 }

    assert_response :success
  end

  test "diff renders successfully when diff raises an error" do
    @post.define_singleton_method(:diff_from) { |version:| raise StandardError, "simulated failure #{version}" }

    Post.stubs(:find).returns(@post)
    get diff_post_path(@post), params: { from_version: 1, to_version: 2 }

    assert_response :success
  end

  test "destroy removes post" do
    assert_difference("Post.count", -1) do
      delete post_path(@post)
    end

    assert_redirected_to posts_path
  end
end
