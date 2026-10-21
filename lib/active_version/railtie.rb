module ActiveVersion
  # Rails integration
  class Railtie < Rails::Railtie
    # Load ActiveVersion after ActiveRecord is loaded
    config.after_initialize do
      ActiveVersion.config.validate!
    end

    # Expose configuration in Rails config
    config.active_version = ActiveVersion.config

    # Drop fiber/thread persistent context when the request or job unit ends so a
    # reused Puma/Sidekiq thread does not stamp the previous actor onto later audits.
    initializer "active_version.clear_context_on_complete" do |app|
      app.executor.to_complete do
        ActiveVersion.clear_context!
      end
    end

    # Add rake tasks
    rake_tasks do
      load "active_version/tasks/active_version.rake"
    end
  end
end
