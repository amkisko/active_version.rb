module ActiveVersion
  # Rails integration
  class Railtie < Rails::Railtie
    # Load ActiveVersion after ActiveRecord is loaded
    config.after_initialize do
      ActiveVersion.config.validate!
    end

    # Expose configuration in Rails config
    config.active_version = ActiveVersion.config

    # Add rake tasks
    rake_tasks do
      load "active_version/tasks/active_version.rake"
    end
  end
end
