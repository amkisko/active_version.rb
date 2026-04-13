module ActiveVersion
  # Unified query builder for version records
  module Query
    class << self
      # Query audits for a record
      # @param record [ActiveRecord::Base] The record to query audits for
      # @param opts [Hash] Query options
      # @option opts [Array] :preload Associations to preload
      # @option opts [Hash] :order_by Order specification
      # @return [ActiveRecord::Relation] Audit relation
      def audits(record, opts = {})
        audit_class = record.class.audit_class
        return audit_class.none unless audit_class

        auditable_column = ActiveVersion.column_mapper.column_for(record.class, :audits, :auditable)
        identity_map = if record.respond_to?(:active_version_audit_identity_map)
          record.active_version_audit_identity_map
        else
          primary_keys = Array(record.class.primary_key).map(&:to_s)
          if primary_keys.one?
            {"#{auditable_column}_id" => record.id}
          else
            primary_keys.zip(primary_keys.map { |column| record[column] }).to_h
          end
        end

        query = audit_class.where({"#{auditable_column}_type" => record.class.name}.merge(identity_map))

        query = query.preload(opts[:preload]) if opts[:preload]
        query = query.order(opts[:order_by]) if opts[:order_by]

        query
      end

      # Query translations for a record
      # @param record [ActiveRecord::Base] The record to query translations for
      # @param opts [Hash] Query options
      # @option opts [String, Symbol] :locale Locale to filter by
      # @return [ActiveRecord::Relation] Translation relation
      def translations(record, opts = {})
        translation_class = record.class.translation_class
        return translation_class.none unless translation_class

        identity_map = if record.respond_to?(:active_version_translation_identity_map)
          record.active_version_translation_identity_map
        else
          keys = Array(translation_class.source_foreign_key).map(&:to_s)
          if keys.one?
            {keys.first => record.id}
          else
            values = Array(record.class.primary_key).map { |column| record[column] }
            keys.zip(values).to_h
          end
        end
        query = translation_class.where(identity_map)

        if opts[:locale]
          locale_column = ActiveVersion.column_mapper.column_for(record.class, :translations, :locale)
          query = query.where(locale_column => opts[:locale])
        end

        query
      end

      # Query revisions for a record
      # @param record [ActiveRecord::Base] The record to query revisions for
      # @param opts [Hash] Query options
      # @option opts [Integer] :version Version number to filter by
      # @return [ActiveRecord::Relation] Revision relation
      def revisions(record, opts = {})
        revision_class = record.class.revision_class
        return revision_class.none unless revision_class

        identity_map = if record.respond_to?(:active_version_revision_identity_map)
          record.active_version_revision_identity_map
        else
          keys = Array(revision_class.source_foreign_key).map(&:to_s)
          if keys.one?
            {keys.first => record.id}
          else
            values = Array(record.class.primary_key).map { |column| record[column] }
            keys.zip(values).to_h
          end
        end
        query = revision_class.where(identity_map)

        if opts[:version]
          version_column = ActiveVersion.column_mapper.column_for(record.class, :revisions, :version)
          query = query.where(version_column => opts[:version])
        end

        version_column = ActiveVersion.column_mapper.column_for(record.class, :revisions, :version)
        query.order(version_column => :asc)
      end
    end
  end
end
