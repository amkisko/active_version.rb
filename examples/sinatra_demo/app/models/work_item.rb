module SinatraDemo
  class WorkItemRevision < Sequel::Model(:work_item_revisions)
    plugin :timestamps, update_on_create: true
  end

  class WorkItemAudit < Sequel::Model(:work_item_audits)
    plugin :timestamps, update_on_create: true
  end

  class WorkItemTranslation < Sequel::Model(:work_item_translations)
    plugin :validation_helpers
    plugin :timestamps, update_on_create: true

    def validate
      super
      validates_presence %i[work_item_id locale title]
    end
  end

  class WorkItem < Sequel::Model(:work_items)
    plugin :validation_helpers
    plugin :timestamps, update_on_create: true
    plugin ActiveVersion::Adapters::Sequel::Versioning

    active_version(
      revision_model: SinatraDemo::WorkItemRevision,
      audit_model: SinatraDemo::WorkItemAudit,
      translation_model: SinatraDemo::WorkItemTranslation,
      foreign_key: :work_item_id,
      tracked_columns: %i[kind title body labels assignee],
      translation_columns: %i[title body labels]
    )

    KINDS = %w[post issue pull_request].freeze

    def validate
      super
      validates_presence %i[kind title]
      validates_includes KINDS, :kind
    end

    def kind_label
      case kind
      when "post" then "Post"
      when "issue" then "Issue"
      when "pull_request" then "Pull Request"
      else kind.to_s
      end
    end
  end
end
