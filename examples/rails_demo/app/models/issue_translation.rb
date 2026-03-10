class IssueTranslation < ApplicationRecord
  include AttachmentUploader::Attachment(:attachment)
  include TrackAttachmentReferences
  include LabelSet
  include ActiveVersion::Translations::TranslationRecord

  configure_translation(locale_column: :locale,
    foreign_key: :issue_id
  )
end
