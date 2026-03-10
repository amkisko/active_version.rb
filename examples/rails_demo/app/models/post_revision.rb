
class PostRevision < ApplicationRecord
  include ComplexDemoFields
  include AttachmentUploader::Attachment(:attachment)
  include TrackAttachmentReferences
  include LabelSet

  include ActiveVersion::Revisions::RevisionRecord

  configure_revision(version_column: :version,
    foreign_key: :post_id
  )

  scope :latest, -> { order(version: :desc) }
  scope :oldest, -> { order(version: :asc) }
end
