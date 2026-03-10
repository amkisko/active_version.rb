require "spec_helper"

RSpec.describe "Sinatra social feed", type: :feature do
  it "renders the main navigation and feed sections" do
    visit "/"

    expect(page).to have_text("Social Feed")
    expect(page).to have_link("Posts")
    expect(page).to have_link("Issues")
    expect(page).to have_link("Pull Requests")
    expect(page).to have_link("Profile")
  end

  it "creates and edits a post through the UI" do
    visit "/posts/new"
    fill_in "Title", with: "Launch notes"
    fill_in "Body", with: "Shipping the Sinatra demo with E2E coverage."
    fill_in "Labels", with: "release, demo"
    fill_in "Assignee", with: "demo.user"
    click_button "Create"

    expect(page).to have_text("Launch notes")
    click_link "Edit"

    fill_in "Title", with: "Launch notes updated"
    click_button "Save"

    expect(page).to have_text("Launch notes updated")
    expect(page).to have_text("Revisions")
    expect(page).to have_text("Audits")
  end

  it "creates an issue and a pull request and shows them in profile" do
    visit "/issues/new"
    fill_in "Title", with: "Search does not rank exact matches first"
    click_button "Create"
    expect(page).to have_text("Search does not rank exact matches first")

    visit "/pull_requests/new"
    fill_in "Title", with: "Improve spacing in timeline cards"
    click_button "Create"
    expect(page).to have_text("Improve spacing in timeline cards")

    visit "/profile"
    expect(page).to have_text("Search does not rank exact matches first")
    expect(page).to have_text("Improve spacing in timeline cards")
  end

  it "creates a translation and renders revisions audits translations on item page" do
    visit "/posts/new"
    fill_in "Title", with: "Translate me"
    fill_in "Body", with: "Body EN"
    click_button "Create"

    expect(page).to have_text("Translations")
    fill_in "Locale", with: "fi"
    fill_in "translation_title", with: "Kaanna minut"
    fill_in "translation_body", with: "Runko FI"
    click_button "Save Translation"

    expect(page).to have_text("Kaanna minut")
    expect(page).to have_text("Revisions")
    expect(page).to have_text("Audits")
    expect(page).to have_text("Translations")
  end
end
