class SourceIdentityPostTranslation < ApplicationRecord
  include ActiveVersion::Translations::TranslationRecord

  configure_translation(locale_column: :locale,
    foreign_key: [:tenant_id, :source_key, :partition_key],
    identity_resolver: [:tenant_id, :source_key, :partition_key]
  )
end
