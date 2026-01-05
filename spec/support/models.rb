# Define version classes first
class PostTranslation < ApplicationRecord
  self.table_name = "post_translations"
  include ActiveVersion::Translations::TranslationRecord
end

class PostRevision < ApplicationRecord
  self.table_name = "post_revisions"
  include ActiveVersion::Revisions::RevisionRecord
end

class PostAudit < ApplicationRecord
  self.table_name = "post_audits"
  include ActiveVersion::Audits::AuditRecord
end

# Then define main model with versioning
class Post < ApplicationRecord
  self.table_name = "posts"

  include ActiveVersion::Translations::HasTranslations
  include ActiveVersion::Revisions::HasRevisions
  include ActiveVersion::Audits::HasAudits

  has_translations
  has_revisions
  has_audits

  # Set up translated scopes for tests
  translated_scopes :title, :body
  translated_copies :title, :body
end
