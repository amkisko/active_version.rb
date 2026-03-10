module ActiveVersion
  # Registry for tracking versioned models and their configuration
  class VersionRegistry
    def initialize
      @models = {}
      @version_classes = {}
    end

    # Register a model with versioning
    # Detects conflicts when re-registering with different options or duplicate registrations
    def register(model_class, version_type, options = {})
      key = registry_key(model_class, version_type)

      # Check for existing registration
      if @models.key?(key)
        existing = @models[key]

        # Detect option conflicts
        if existing[:options] != options
          warn "[ActiveVersion] Re-registering #{model_class.name} with :#{version_type} " \
               "with different options. Previous: #{existing[:options].inspect}, " \
               "New: #{options.inspect}. This may indicate a configuration issue."
        else
          # Same options - likely a double include, but not necessarily a problem
          # Log at debug level if needed
        end
      end

      @models[key] = {
        model_class: model_class,
        version_type: version_type,
        options: options,
        registered_at: Time.current
      }
    end

    # Get version class for a model and version type
    def version_class_for(model_class, version_type)
      key = registry_key(model_class, version_type)
      @version_classes[key]
    end

    # Register a version class
    def register_version_class(model_class, version_type, version_class)
      key = registry_key(model_class, version_type)
      @version_classes[key] = version_class
    end

    # Check if a model is registered for versioning
    def registered?(model_class, version_type)
      key = registry_key(model_class, version_type)
      @models.key?(key)
    end

    # Get all registered models for a version type
    def models_for_version_type(version_type)
      @models.select { |_k, v| v[:version_type] == version_type }
        .map { |_k, v| v[:model_class] }
    end

    # Get configuration for a model and version type
    def config_for(model_class, version_type)
      key = registry_key(model_class, version_type)
      @models[key]&.fetch(:options, {})
    end

    # Get configuration by model class name and version type.
    # Useful while constants are still being wired and only the intended class
    # name is known.
    def config_for_model_name(model_name, version_type)
      key = :"#{model_name}:#{version_type}"
      @models[key]&.fetch(:options, {})
    end

    # Clear all registrations (useful for testing)
    def clear!
      @models.clear
      @version_classes.clear
    end

    private

    def registry_key(model_class, version_type)
      :"#{model_class.name}:#{version_type}"
    end
  end
end
