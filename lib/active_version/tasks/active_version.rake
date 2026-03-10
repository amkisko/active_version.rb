namespace :active_version do
  desc "Display ActiveVersion configuration"
  task :config do
    puts "ActiveVersion Configuration:"
    puts "  Auditing Enabled: #{ActiveVersion.auditing_enabled}"
    puts "  Audit Storage: #{ActiveVersion.config.audit_storage}"
    puts "  Current User Method: #{ActiveVersion.config.current_user_method}"
    puts ""
    puts "Registered Models:"
    ActiveVersion.registry.models_for_version_type(:translations).each do |model|
      puts "  - #{model.name} (translations)"
    end
    ActiveVersion.registry.models_for_version_type(:revisions).each do |model|
      puts "  - #{model.name} (revisions)"
    end
    ActiveVersion.registry.models_for_version_type(:audits).each do |model|
      puts "  - #{model.name} (audits)"
    end
  end

  desc "Validate ActiveVersion configuration"
  task :validate do
    ActiveVersion.config.validate!
    puts "✓ Configuration is valid"
  rescue ActiveVersion::ConfigurationError => e
    puts "✗ Configuration error: #{e.message}"
    exit 1
  end
end
