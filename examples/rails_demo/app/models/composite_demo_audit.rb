class CompositeDemoAudit < ApplicationRecord
  self.primary_key = [:audit_id, :partition_key]

  validates :audit_id, :partition_key, :auditable_type, :auditable_id, :version, presence: true
  validates :version, uniqueness: { scope: [:auditable_type, :auditable_id, :partition_key] }

  scope :recent, -> { order(partition_key: :desc, audit_id: :desc) }

  def to_param
    self.class.id_to_param(id)
  end

  def composite_id
    self.class.id_to_param(id)
  end
end
