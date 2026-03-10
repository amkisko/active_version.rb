
ActiveVersion.configure do |config|
  # Global settings
  config.auditing_enabled = true
  config.current_user_method = :current_user

  # Translation settings
  config.translation_locale_column = :locale
  config.translation_default_locale = :en

  # Revision settings
  config.revision_version_column = :version

  # Audit settings
  # Default audit model for has_audits when no model-specific XxxAudit exists (e.g. Category).
  # Uses the generic audits table; Post keeps using PostAudit (post_audits table) via convention.
  config.default_audit_class = "Audit"
end
