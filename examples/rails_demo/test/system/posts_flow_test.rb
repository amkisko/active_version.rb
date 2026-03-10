require "application_system_test_case"

class PostsFlowTest < ApplicationSystemTestCase
  test "user creates and updates post through browser flow" do
    visit root_path
    click_link "New Post"

    fill_in "Title", with: "System test post"
    fill_in "Body", with: "System test body"
    select "Draft", from: "Status"
    fill_in "Audit comment", with: "created via system test"
    click_button "Create Post"

    assert_text "Post was successfully created."
    assert_text "System test post"

    click_link "Edit"
    fill_in "Title", with: "System test post updated"
    fill_in "Audit comment", with: "updated via system test"
    click_button "Update Post"

    assert_text "Post was successfully updated."
    assert_text "System test post updated"
  end

  test "user can access revisions and audits pages from post" do
    post = Post.create!(title: "History Post", body: "v1", author: User.first || User.create!(name: "System User", email: "system_user@example.com", password: "password"))
    post.update!(title: "History Post v2")

    visit post_path(post)
    click_link "Revisions", match: :first
    assert_text "Revisions"

    visit post_path(post)
    click_link "Audits", match: :first
    assert_text "Audits"
  end
end
