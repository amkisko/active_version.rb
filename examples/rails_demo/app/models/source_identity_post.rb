class SourceIdentityPost < ApplicationRecord
  has_translations
  has_revisions
  has_audits only: [:tenant_id, :source_key, :partition_key, :title, :status]

  validates :tenant_id, :source_key, :partition_key, :title, :status, presence: true
  validates :source_key, uniqueness: { scope: [:tenant_id, :partition_key] }

  scope :recent, -> { order(created_at: :desc) }
end
