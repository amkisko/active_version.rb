
class User < ApplicationRecord
  has_audits

  has_secure_password
  has_many :posts, foreign_key: :author_id, inverse_of: :author, dependent: :nullify
  has_many :assigned_posts, class_name: "Post", foreign_key: :assignee_id, inverse_of: :assignee, dependent: :nullify
  has_many :issues, foreign_key: :author_id, inverse_of: :author, dependent: :nullify
  has_many :assigned_issues, class_name: "Issue", foreign_key: :assignee_id, inverse_of: :assignee, dependent: :nullify
  has_many :pull_requests, foreign_key: :author_id, inverse_of: :author, dependent: :nullify
  has_many :assigned_pull_requests, class_name: "PullRequest", foreign_key: :assignee_id, inverse_of: :assignee, dependent: :nullify

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
end
