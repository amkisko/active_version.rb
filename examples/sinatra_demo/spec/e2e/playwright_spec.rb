require "spec_helper"

RSpec.describe "Sinatra demo with Playwright", type: :feature, js: true do
  before do
    skip("capybara-playwright-driver is not available") unless Object.const_defined?(:PLAYWRIGHT_AVAILABLE) && PLAYWRIGHT_AVAILABLE
  end

  it "navigates across resources in a real browser" do
    visit "/"
    click_link "Posts"
    expect(page).to have_text("Posts")

    click_link "New Post"
    fill_in "Title", with: "Browser verified post"
    click_button "Create"

    expect(page).to have_text("Browser verified post")
    click_link "Back"
    expect(page).to have_text("Browser verified post")
  end
end
