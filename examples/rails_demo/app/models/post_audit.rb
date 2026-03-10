
class PostAudit < ApplicationRecord
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

  scope :creates, -> { where(action: "create") }
  scope :updates, -> { where(action: "update") }
  scope :destroys, -> { where(action: "destroy") }
  scope :with_comments, -> { where.not(comment: [nil, ""]) }
  scope :recent, -> { order(created_at: :desc) }
end
