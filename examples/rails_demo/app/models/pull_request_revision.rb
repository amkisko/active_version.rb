class PullRequestRevision < ApplicationRecord
  include AttachmentUploader::Attachment(:attachment)
  include TrackAttachmentReferences
  include LabelSet
  include ActiveVersion::Revisions::RevisionRecord

  configure_revision(version_column: :version,
    foreign_key: :pull_request_id
  )

  scope :latest, -> { order(version: :desc) }
end
