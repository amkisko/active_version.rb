ENV["RAILS_ENV"] ||= "test"

require "mocha/minitest"

require "simplecov"

SimpleCov.start "rails" do
  enable_coverage :branch
  track_files "app/models/**/*.rb"
  track_files "app/controllers/**/*.rb"
  minimum_coverage line: 30  # Demo app; raise for production
end

require_relative "../config/environment"
require "rails/test_help"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

module ActiveSupport
  class TestCase
    parallelize(workers: 1)
  end
end
