module ActiveVersion
  # Maps versioning concepts to actual column names
  # Allows developers to configure any column name to any concept
  class ColumnMapper
    def initialize
      @mappings = {}
    end

    # Register a column mapping for a model and version type
    def register(model_class, version_type, concept, column_name)
      key = mapping_key(model_class, version_type, concept)
      @mappings[key] = column_name.to_sym
    end

    # Get column name for a concept
    def column_for(model_class, version_type, concept)
      key = mapping_key(model_class, version_type, concept)
      @mappings[key] || default_column_for(version_type, concept)
    end

    # Get all mappings for a model and version type
    def mappings_for(model_class, version_type)
      prefix = "#{model_class.name}:#{version_type}:"
      @mappings.select { |k, _v| k.to_s.start_with?(prefix) }
        .transform_keys { |k| k.to_s.sub(prefix, "").to_sym }
    end

    private

    def mapping_key(model_class, version_type, concept)
      :"#{model_class.name}:#{version_type}:#{concept}"
    end

    def default_column_for(version_type, concept)
      case version_type
      when :translations
        default_translation_column(concept)
      when :revisions
        default_revision_column(concept)
      when :audits
        default_audit_column(concept)
      else
        raise ConfigurationError, "Unknown version type: #{version_type.inspect}"
      end
    end

    def default_translation_column(concept)
      case concept
      when :locale
        ActiveVersion.config.translation_locale_column
      else
        raise ConfigurationError, "Unknown translation concept: #{concept.inspect}"
      end
    end

    def default_revision_column(concept)
      case concept
      when :version
        ActiveVersion.config.revision_version_column
      else
        raise ConfigurationError, "Unknown revision concept: #{concept.inspect}"
      end
    end

    def default_audit_column(concept)
      case concept
      when :action
        ActiveVersion.config.audit_action_column
      when :changes
        ActiveVersion.config.audit_changes_column
      when :context
        ActiveVersion.config.audit_context_column
      when :comment
        ActiveVersion.config.audit_comment_column
      when :version
        ActiveVersion.config.audit_version_column
      when :user
        ActiveVersion.config.audit_user_column
      when :auditable
        ActiveVersion.config.audit_auditable_column
      when :associated
        ActiveVersion.config.audit_associated_column
      when :remote_address
        ActiveVersion.config.audit_remote_address_column
      when :request_uuid
        ActiveVersion.config.audit_request_uuid_column
      else
        raise ConfigurationError, "Unknown audit concept: #{concept.inspect}"
      end
    end
  end
end
