# Generic audit record for models using has_audits without a dedicated XxxAudit class.
# Used when ActiveVersion.config.default_audit_class is set to "Audit".
class Audit < ApplicationRecord
  include ActiveVersion::Audits::AuditRecord

  configure_audit do
    storage :json_column
    action_column :action
    changes_column :audited_changes
    context_column :audited_context
    comment_column :comment
    version_column :version
    user_column :user_id
  end
end
