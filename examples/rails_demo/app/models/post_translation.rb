
class PostTranslation < ApplicationRecord
  include ComplexDemoFields
  include AttachmentUploader::Attachment(:attachment)
  include TrackAttachmentReferences
  include LabelSet

  include ActiveVersion::Translations::TranslationRecord

  configure_translation(locale_column: :locale,
    foreign_key: :post_id
  )
end
