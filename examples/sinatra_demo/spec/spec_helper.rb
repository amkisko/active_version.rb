ENV["APP_ENV"] = "test"

require "bundler/setup"
require "capybara/rspec"
require "sequel"
require_relative "../app"

DB[:work_items].delete if DB.table_exists?(:work_items)

Capybara.app = SinatraDemo::App
Capybara.server = :puma, {Silent: true}

begin
  require "capybara-playwright-driver"

  Capybara.register_driver :playwright do |app|
    Capybara::Playwright::Driver.new(app,
      browser_type: :chromium,
      headless: true,
      timeout: 15_000)
  end

  Capybara.javascript_driver = :playwright
  PLAYWRIGHT_AVAILABLE = true
rescue LoadError
  PLAYWRIGHT_AVAILABLE = false
end

RSpec.configure do |config|
  config.order = :random
  config.before(:each) do
    DB[:work_items].delete
  end
end
