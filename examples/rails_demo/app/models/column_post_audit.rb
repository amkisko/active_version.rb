class ColumnPostAudit < ApplicationRecord
  include ActiveVersion::Audits::AuditRecord

  self.table_name = "column_post_audits"

  configure_audit do
    storage :mirror_columns
    action_column :action
    changes_column :audited_changes
    context_column :audited_context
    comment_column :comment
    version_column :version
    user_column :user_id
  end

  scope :with_title, ->(title) { where(title: title) }
  scope :published_only, -> { where(published: true) }
end
