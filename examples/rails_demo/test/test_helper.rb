ENV["RAILS_ENV"] ||= "test"

unless %w[1 true yes].include?(ENV["POLYRUN_COVERAGE_DISABLE"]&.to_s&.downcase)
  require "polyrun"
  Polyrun::Coverage::Rails.start!(root: File.expand_path("..", __dir__))
end

require_relative "../config/environment"
require "rails/test_help"

require "mocha/minitest"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

module ActiveSupport
  class TestCase
    parallelize(workers: 1)
  end
end
