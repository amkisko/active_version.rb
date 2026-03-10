class AdminUser < ApplicationRecord
  has_audits

  validates :email, presence: true, uniqueness: true
end
