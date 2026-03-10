class SourceIdentityPostRevision < ApplicationRecord
  include ActiveVersion::Revisions::RevisionRecord

  configure_revision(version_column: :version,
    foreign_key: [:tenant_id, :source_key, :partition_key],
    foreign_key_value: [:tenant_id, :source_key, :partition_key]
  )
end
