class ColumnPost < ApplicationRecord
  has_audits as: ColumnPostAudit, only: [:title, :published]

  validates :title, presence: true
end
