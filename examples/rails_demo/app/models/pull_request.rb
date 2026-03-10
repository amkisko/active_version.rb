class PullRequest < ApplicationRecord
  include AttachmentUploader::Attachment(:attachment)
  include TrackAttachmentReferences
  include LabelSet

  belongs_to :author, class_name: "User", optional: true
  belongs_to :assignee, class_name: "User", optional: true

  has_translations
  has_revisions
  has_audits

  translated_scopes :title, :body
  translated_copies :title, :body

  validates :title, presence: true
  validates :status, inclusion: { in: %w[open merged closed] }

  scope :recent, -> { order(created_at: :desc) }
end
