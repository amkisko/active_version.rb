unless ENV["SIMPLECOV_DISABLE"] == "1"
  require "simplecov"
  require "simplecov-console"
  require "simplecov-cobertura"
  require "simplecov_json_formatter"

  SimpleCov.start do
    minimum_coverage(90)
    track_files "{lib,app}/**/*.rb"

    add_filter "/lib/active_version/tasks/"
    add_filter "/lib/active_version/version.rb"

    add_filter "/lib/generators/"

    add_filter "/lib/active_version/railtie.rb"
    add_filter "/lib/active_version/adapters/active_record.rb"
    add_filter "/lib/active_version/database/triggers/postgresql.rb"
    add_filter "/lib/active_version/audits/has_audits/database_adapter_helper.rb"
    add_filter "/lib/active_version/migrators/audited.rb"
    add_filter "/lib/active_version/revisions/has_revisions/revision_queries.rb"

    add_filter "/spec/integration/partitioned_tables_postgresql_spec.rb"
    add_filter "/spec/benchmark/"

    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::Console,
      SimpleCov::Formatter::CoberturaFormatter,
      SimpleCov::Formatter::JSONFormatter
    ])
  end
end

require "bundler/setup"
require "active_version"

# Load support files after ApplicationRecord is defined
Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }

# Load Rails constants when available, but never load rails/test_help in RSpec.
# rails/test_help boots Minitest and can hijack CLI options (e.g. --tag, --format).
begin
  require "rails"
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

  config.filter_run_excluding benchmark: true unless ENV["BENCHMARK"] == "1"

  # Run integration specs first so they see clean state (no callback/schema pollution from unit specs).
  # Within integration, run "core" specs first (revisions, audits) before specs that create Post subclasses
  # (e.g. audit_combiner_spec), which can leave registry/state that breaks plain Post revision creation.
  config.register_ordering(:global) do |groups|
    groups.sort_by do |g|
      path = g.metadata[:file_path].to_s
      if path.include?("integration")
        # Core integration specs that use Post directly — run first
        if path.include?("revisions_spec") then 0
        elsif path.include?("audits_spec") then 1
        elsif path.include?("activerecord_compatibility") then 2
        elsif path.include?("translations_spec") then 3
        elsif path.include?("module_compatibility") then 4
        else
          5 # audit_combiner, additional_context, etc.
        end
      else
        10 # unit specs last
      end
    end
  end

  # Clean up between tests - reset context and ensure auditing is on.
  # Do NOT clear the registry: models register at load time and revision/audit
  # callbacks rely on class state; clearing breaks integration specs when run in full suite.
  config.before do
    ActiveVersion.context = {}
    ActiveVersion.clear_context!
    ActiveVersion.auditing_enabled = true
    ActiveVersion.clear_scoped_keys!(/active_version_.*_audited_options/)
  end

  # Integration test configuration
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end
end
