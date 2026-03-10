require "application_system_test_case"

class HomeNavigationTest < ApplicationSystemTestCase
  test "home page renders primary navigation and command line shell" do
    visit root_path

    assert_text "ActiveVersion Demo"
    assert_text "Social Demo Feed"

    assert_selector "nav a", text: "Posts"
    assert_selector "nav a", text: "Issues"
    assert_selector "nav a", text: "Pull Requests"
    assert_selector "#av-cli-form"
    assert_selector "#av-cli-input"
  end

  test "can navigate from home to posts index" do
    visit root_path
    click_link "Posts"

    assert_current_path posts_path
    assert_text "Posts"
  end
end
