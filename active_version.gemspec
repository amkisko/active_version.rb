require_relative "lib/active_version/version"

Gem::Specification.new do |spec|
  spec.name = "active_version"
  spec.version = ActiveVersion::VERSION
  spec.authors = ["Andrei Makarov"]
  spec.email = ["andrei@kiskolabs.com"]

  spec.summary = "Unified versioning library for translations, revisions, and audits"
  spec.description = "ActiveVersion is a language-agnostic versioning library that unifies three core use cases: translations (locale-based), revisions/drafts (workflow snapshots), and audits (change tracking)."
  spec.homepage = "https://github.com/amkisko/active_version.rb"
  spec.license = "MIT"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "sig/**/*", "README.md", "LICENSE.md", "CHANGELOG.md", "SECURITY.md"].select { |f| File.file?(f) }
  end
  spec.files += Dir["lib/tasks/**/*.rake"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "changelog_uri" => "https://github.com/amkisko/active_version.rb/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/amkisko/active_version.rb/issues",
    "documentation_uri" => "https://github.com/amkisko/active_version.rb#readme",
    "rubygems_mfa_required" => "true"
  }

  spec.add_dependency "activesupport", ">= 6.0.0"

  spec.add_development_dependency "rake", "~> 13"
  spec.add_development_dependency "activerecord", ">= 6.0.0"
  spec.add_development_dependency "rspec", "~> 3"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "sqlite3", ">= 1.4"
  spec.add_development_dependency "pg", "~> 1.5"
  spec.add_development_dependency "sequel", "~> 5.84"
  spec.add_development_dependency "benchmark", ">= 0.4"
  spec.add_development_dependency "polyrun", "~> 1.3.0"
  spec.add_development_dependency "standard", "~> 1.52"
  spec.add_development_dependency "standard-custom", "~> 1.0"
  spec.add_development_dependency "standard-performance", "~> 1.8"
  spec.add_development_dependency "standard-rails", "~> 1.5"
  spec.add_development_dependency "standard-rspec", "~> 0.3"
  spec.add_development_dependency "rubocop-rails", "~> 2.33"
  spec.add_development_dependency "rubocop-rspec", "~> 3.8"
  spec.add_development_dependency "rubocop-thread_safety", "~> 0.7"
  spec.add_development_dependency "appraisal", "~> 2"
  spec.add_development_dependency "rbs", "~> 3"
end
