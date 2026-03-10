class SourceIdentityPostAudit < ApplicationRecord
  include ActiveVersion::Audits::AuditRecord

  configure_audit do
    storage :mirror_columns
    action_column :action
    changes_column :audited_changes
    context_column :audited_context
    comment_column :comment
    version_column :version
    user_column :user_id
  end
end
