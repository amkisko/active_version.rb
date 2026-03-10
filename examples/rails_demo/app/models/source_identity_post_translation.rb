class SourceIdentityPostTranslation < ApplicationRecord
  include ActiveVersion::Translations::TranslationRecord

  configure_translation(locale_column: :locale,
    foreign_key: [:tenant_id, :source_key, :partition_key],
    foreign_key_value: [:tenant_id, :source_key, :partition_key]
  )
end
