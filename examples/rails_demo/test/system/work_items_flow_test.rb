require "application_system_test_case"

class WorkItemsFlowTest < ApplicationSystemTestCase
  setup do
    @assignee = User.first || User.create!(name: "Assignee User", email: "assignee_user@example.com", password: "password")
  end

  test "user creates an issue" do
    visit root_path
    click_link "New Issue"

    fill_in "Title", with: "System issue"
    fill_in "Body", with: "Issue body from system test"
    select "Open", from: "Status"
    select @assignee.name, from: "Assignee"
    fill_in "Audit comment", with: "issue created by system test"
    click_button "Create Issue"

    assert_text "Issue was successfully created."
    assert_text "System issue"
  end

  test "user creates a pull request" do
    visit root_path
    click_link "New Pull Request"

    fill_in "Title", with: "System pull request"
    fill_in "Body", with: "Pull request body from system test"
    fill_in "Source branch", with: "feature/system-test"
    fill_in "Target branch", with: "main"
    select "Open", from: "Status"
    select @assignee.name, from: "Assignee"
    fill_in "Audit comment", with: "pr created by system test"
    click_button "Create Pull Request"

    assert_text "Pull request was successfully created."
    assert_text "System pull request"
  end
end
