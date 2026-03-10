if defined?(ActiveRecord)
  unless defined?(ApplicationRecord)
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
      class_attribute :param_delimiter, instance_writer: false, default: ":"

      def test_callback
        # no-op callback used in integration tests
      end

      def self.param_to_id(param)
        param&.include?(param_delimiter) ? param.split(param_delimiter) : param
      end

      def self.id_to_param(id)
        id.is_a?(Array) ? id.join(param_delimiter) : id
      end
    end
  end

  # Define version classes first
  class PostTranslation < ApplicationRecord
    self.table_name = "post_translations"
    include ActiveVersion::Translations::TranslationRecord
  end

  class PostRevision < ApplicationRecord
    self.table_name = "post_revisions"
    include ActiveVersion::Revisions::RevisionRecord

    # Override destroy_all to bypass readonly for test cleanup
    def self.destroy_all
      connection.execute("DELETE FROM #{table_name}")
    end
  end

  class PostAudit < ApplicationRecord
    self.table_name = "post_audits"
    include ActiveVersion::Audits::AuditRecord

    # Override destroy_all to bypass readonly for test cleanup
    def self.destroy_all
      connection.execute("DELETE FROM #{table_name}")
    end
  end

  # Then define main model with versioning
  class Post < ApplicationRecord
    self.table_name = "posts"

    include ActiveVersion::Translations::HasTranslations
    include ActiveVersion::Revisions::HasRevisions
    include ActiveVersion::Audits::HasAudits

    has_translations
    has_revisions # Will use default options (auto: true, on: [:update])
    has_audits as: PostAudit # Will use default options (auto: true, on: [:create, :update, :destroy])

    # Set up translated scopes for tests
    translated_scopes :title, :body
    translated_copies :title, :body
  end

  # Ensure PostRevision associations are set up after Post is defined
  # This is needed because PostRevision needs Post to exist for belongs_to
  PostRevision.setup_associations if PostRevision.respond_to?(:setup_associations)
end
