require "simplecov"
require "simplecov-console"
require "simplecov-cobertura"
require "simplecov_json_formatter"

SimpleCov.start do
  track_files "{lib,app}/**/*.rb"
  add_filter "/lib/active_version/tasks/"
  add_filter "/lib/active_version/version.rb"

  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Console,
    SimpleCov::Formatter::CoberturaFormatter,
    SimpleCov::Formatter::JSONFormatter
  ])

  minimum_coverage 95
end

require "bundler/setup"
require "active_version"

# Load Rails if available
begin
  require "rails"
  if defined?(Rails) && Rails.respond_to?(:application)
    require "rails/test_help"
  end
rescue LoadError, NoMethodError
  # Not in Rails environment or Rails not fully initialized
end

# Configure Time.zone if ActiveSupport is available
if defined?(ActiveSupport::TimeZone)
  Time.zone ||= ActiveSupport::TimeZone["UTC"]
end

# Ensure ActiveRecord adapters are loaded for tests
# The adapters should auto-include when ActiveRecord::Base is loaded,
# but we verify they're available
if defined?(ActiveRecord::Base)
  # Define ApplicationRecord if it doesn't exist (for non-Rails environments)
  unless defined?(ApplicationRecord)
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end

  # The adapters are already required in active_version.rb and should auto-include
  # This is just a verification that they're available
  unless ActiveRecord::Base.respond_to?(:has_translations) ||
      ActiveRecord::Base.respond_to?(:has_revisions) ||
      ActiveRecord::Base.respond_to?(:has_audits)
    # If adapters aren't loaded, force load them
    require "active_version/adapters/active_record/translations"
    require "active_version/adapters/active_record/revisions"
    require "active_version/adapters/active_record/audits"
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Clean up between tests
  config.before do
    ActiveVersion.registry&.clear!
    ActiveVersion.context = {}
  end

  # Integration test configuration
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end
end
