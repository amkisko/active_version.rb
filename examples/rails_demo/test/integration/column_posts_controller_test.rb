require "test_helper"

class ColumnPostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @column_post = ColumnPost.create!(
      title: "Column Demo",
      body: "Body",
      internal_notes: "Private",
      published: false
    )
    @column_post.update!(title: "Column Demo v2", published: true)
  end

  test "index renders successfully" do
    get column_posts_path
    assert_response :success
  end

  test "show renders successfully and supports filters" do
    get column_post_path(@column_post)
    assert_response :success

    get column_post_path(@column_post), params: { title_filter: "Column Demo v2", published_filter: "true" }
    assert_response :success
  end

  test "edit renders successfully" do
    get edit_column_post_path(@column_post)
    assert_response :success
  end

  test "update modifies record and redirects" do
    patch column_post_path(@column_post), params: {
      column_post: {
        title: "Updated",
        body: "Updated body",
        internal_notes: "Not audited",
        published: false,
        audit_comment: "test comment"
      }
    }

    assert_redirected_to column_post_path(@column_post)
    assert_equal "Updated", @column_post.reload.title
  end
end
