class SourceIdentityPostRevision < ApplicationRecord
  include ActiveVersion::Revisions::RevisionRecord

  configure_revision(version_column: :version,
    foreign_key: [:tenant_id, :source_key, :partition_key],
    identity_resolver: [:tenant_id, :source_key, :partition_key]
  )
end
