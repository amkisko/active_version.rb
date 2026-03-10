require "capybara/minitest"
require "capybara/playwright"

Capybara.default_max_wait_time = ENV.fetch("CAPYBARA_MAX_WAIT_TIME", "5").to_i

Capybara.register_driver :playwright do |app|
  Capybara::Playwright::Driver.new(
    app,
    browser_type: ENV.fetch("PLAYWRIGHT_BROWSER", "chromium").to_sym,
    headless: (ENV["HEADFUL"].presence || "false").downcase == "false"
  )
end
