require "bundler/setup"
require "logger"

# Default: quiet SQL/schema/migration/Rails chatter. Set SPEC_VERBOSE=1 to restore loggers and schema output.
module SpecTestLogging
  NULL = Logger.new(File::NULL)

  def self.enabled?
    !%w[1 true yes].include?(ENV["SPEC_VERBOSE"]&.to_s&.downcase)
  end

  def self.silence!
    return unless enabled?

    silence_active_record!
    silence_rails_log_level!
    silence_active_version_log!
  end

  def self.silence_active_version_logger!
    return unless enabled?

    silence_active_version_log!
  end

  def self.silence_active_record!
    if defined?(ActiveRecord::Base)
      ActiveRecord::Base.logger = NULL
      ActiveRecord.verbose_query_logs = false if ActiveRecord.respond_to?(:verbose_query_logs=)
    end
    if defined?(ActiveRecord::Migration) && ActiveRecord::Migration.respond_to?(:verbose=)
      ActiveRecord::Migration.verbose = false
    end
    if defined?(ActiveRecord::Schema) && ActiveRecord::Schema.respond_to?(:verbose=)
      ActiveRecord::Schema.verbose = false
    end
    return unless defined?(ActiveRecord::LogSubscriber)

    ActiveRecord::LogSubscriber.logger = NULL
  end

  def self.silence_rails_log_level!
    return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

    Rails.logger.level = Logger::WARN
  end

  def self.silence_active_version_log!
    return unless defined?(ActiveVersion)

    ActiveVersion.logger = nil
  end
end

# When POLYRUN_RSPEC_JSON=1, each parallel worker (POLYRUN_SHARD_INDEX) writes tmp/rspec-<i>.json for CI report-junit.
if ENV["POLYRUN_RSPEC_JSON"] == "1" && ENV["POLYRUN_SHARD_INDEX"]
  require "fileutils"
  idx = ENV.fetch("POLYRUN_SHARD_INDEX")
  json_out = File.expand_path("../tmp/rspec-#{idx}.json", __dir__)
  FileUtils.mkdir_p(File.dirname(json_out))
  RSpec.configure do |config|
    config.add_formatter(:json, json_out)
  end
end

unless ENV["POLYRUN_COVERAGE_DISABLE"] == "1"
  require "polyrun"
  Polyrun::Coverage::Rails.start!
end

# Load Rails before the gem so `lib/active_version.rb` can require the railtie (coverage + realistic load order).
begin
  require "rails"
rescue LoadError, NoMethodError
  # Not in Rails environment or Rails not fully initialized
end

require "active_version"
SpecTestLogging.silence_active_version_logger! if defined?(SpecTestLogging)

# Load support files after ApplicationRecord is defined
Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }

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
  config.before(:suite) { SpecTestLogging.silence! }

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
    if defined?(ActiveVersion::RequestStore)
      ActiveVersion::RequestStore.audited_user = nil if ActiveVersion::RequestStore.respond_to?(:audited_user=)
      ActiveVersion::RequestStore.request_uuid = nil if ActiveVersion::RequestStore.respond_to?(:request_uuid=)
      ActiveVersion::RequestStore.remote_address = nil if ActiveVersion::RequestStore.respond_to?(:remote_address=)
    end

    # Keep shared test model configuration deterministic across examples.
    if defined?(Post)
      Post.has_translations(as: PostTranslation) if defined?(PostTranslation) && Post.respond_to?(:has_translations)
      Post.has_revisions(as: PostRevision) if defined?(PostRevision) && Post.respond_to?(:has_revisions)
      Post.has_audits(as: PostAudit) if defined?(PostAudit) && Post.respond_to?(:has_audits)
    end
  end

  # Integration test configuration
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end
end
