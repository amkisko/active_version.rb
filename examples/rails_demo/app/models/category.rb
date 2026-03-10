
class Category < ApplicationRecord
  has_audits

  has_many :posts, dependent: :destroy

  validates :name, presence: true
end

