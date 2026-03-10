module ActiveVersion
  # Global configuration for ActiveVersion
  class Configuration
    attr_accessor :auditing_enabled
    attr_accessor :current_user_method
    attr_accessor :ignored_attributes
    attr_accessor :ignored_default_callbacks
    attr_accessor :store_synthesized_enums
    attr_accessor :execution_scope

    # Translation defaults
    attr_accessor :translation_locale_column
    attr_accessor :translation_default_locale

    # Revision defaults
    attr_accessor :revision_version_column
    attr_accessor :revision_foreign_key_suffix

    # Audit defaults
    attr_accessor :default_audit_class
    attr_accessor :audit_storage
    attr_accessor :audit_action_column
    attr_accessor :audit_changes_column
    attr_accessor :audit_context_column
    attr_accessor :audit_comment_column
    attr_accessor :audit_version_column
    attr_accessor :audit_user_column
    attr_accessor :audit_auditable_column
    attr_accessor :audit_associated_column
    attr_accessor :audit_remote_address_column
    attr_accessor :audit_request_uuid_column
    attr_accessor :max_audits
    attr_accessor :max_revisions
    attr_accessor :return_self_if_no_revisions
    attr_accessor :return_self_if_no_audits
    attr_accessor :audit_error_behavior
    attr_accessor :revision_error_behavior
    attr_accessor :debounce_time

    def initialize
      # Global settings
      @auditing_enabled = true
      @current_user_method = :current_user
      @ignored_attributes = %w[lock_version created_at updated_at created_on updated_on]
      @ignored_default_callbacks = []
      @store_synthesized_enums = false
      @execution_scope = :fiber

      # Translation defaults
      @translation_locale_column = :locale
      @translation_default_locale = :en

      # Revision defaults
      @revision_version_column = :version
      @revision_foreign_key_suffix = "_id"

      # Audit defaults
      @default_audit_class = nil  # When set, has_audits without :as uses this when ModelAudit is not defined
      @audit_storage = :json_column
      @audit_action_column = :action
      @audit_changes_column = :audited_changes
      @audit_context_column = :audited_context
      @audit_comment_column = :comment
      @audit_version_column = :version
      @audit_user_column = :user_id
      @audit_auditable_column = :auditable
      @audit_associated_column = :associated
      @audit_remote_address_column = :remote_address
      @audit_request_uuid_column = :request_uuid
      @max_audits = nil
      @max_revisions = nil
      @return_self_if_no_revisions = false
      @return_self_if_no_audits = false
      @audit_error_behavior = :exception
      @revision_error_behavior = :exception
      @debounce_time = nil  # Time in seconds to merge revisions within window
    end

    # Validate configuration
    def validate!
      validate_storage_type!
      validate_execution_scope!
      validate_column_names!
    end

    private

    def validate_storage_type!
      unless %i[json_column yaml_column mirror_columns].include?(@audit_storage)
        raise ConfigurationError,
          "audit_storage must be :json_column, :yaml_column, or :mirror_columns, got: #{@audit_storage.inspect}"
      end
    end

    def validate_execution_scope!
      return if %i[fiber thread].include?(@execution_scope)

      raise ConfigurationError,
        "execution_scope must be :fiber or :thread, got: #{@execution_scope.inspect}"
    end

    def validate_column_names!
      # Ensure column names are symbols or strings
      column_attrs = [
        :translation_locale_column,
        :revision_version_column,
        :audit_action_column,
        :audit_changes_column,
        :audit_context_column,
        :audit_comment_column,
        :audit_version_column,
        :audit_user_column
      ]

      column_attrs.each do |attr|
        value = instance_variable_get(:"@#{attr}")
        unless value.is_a?(Symbol) || value.is_a?(String)
          raise ConfigurationError,
            "#{attr} must be a Symbol or String, got: #{value.class}"
        end
      end
    end
  end
end
