
class Post < ApplicationRecord
  include ComplexDemoFields
  include AttachmentUploader::Attachment(:attachment)
  include TrackAttachmentReferences
  include LabelSet

  belongs_to :category, optional: true
  belongs_to :author, class_name: "User", optional: true
  belongs_to :assignee, class_name: "User", optional: true

  # ActiveVersion features
  has_translations
  has_revisions
  has_audits associated_with: :category

  # Generate scopes for translated attributes
  translated_scopes :title, :body

  # Copy translated values to source when blank
  translated_copies :title, :body

  validates :title, presence: true
  validates :status, inclusion: { in: %w[draft published archived] }

  scope :recent, -> { order(created_at: :desc) }
  scope :with_translations, -> { joins(:translations).distinct }
  scope :with_revisions, -> { joins(:revisions).distinct }
end
