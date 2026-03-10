require "active_version/migrators/base"

module ActiveVersion
  module Migrators
    # Migrator from audited gem
    class Audited < Base
      class << self
        # Migrate audits from audited gem
        # @param model_class [Class] ActiveRecord model class
        # @param options [Hash] Migration options
        # @option options [Boolean] :dry_run (false) Don't actually migrate
        # @return [Integer] Number of records migrated
        def migrate(model_class, options = {})
          return 0 unless model_class.respond_to?(:audited?)

          audit_class = model_class.audit_class
          return 0 unless audit_class

          old_audits = source_audits(model_class)
          count = 0

          if old_audits.respond_to?(:find_each)
            old_audits.find_each do |old_audit|
              count += 1
              next if options[:dry_run]

              audit_data = convert_audit(old_audit, model_class)
              create_audit(nil, audit_data, audit_class)
            end
          else
            # Handle array case (from mocked source_audits in tests)
            old_audits.each do |old_audit|
              count += 1
              next if options[:dry_run]

              audit_data = convert_audit(old_audit, model_class)
              create_audit(nil, audit_data, audit_class)
            end
          end

          count
        end

        private

        def source_audits(model_class)
          # Try to find old audit class
          old_audit_class = if defined?(::Audited::Audit)
            ::Audited::Audit
          else
            begin
              "#{model_class.name}Audit".constantize
            rescue
              nil
            end
          end

          return [] unless old_audit_class

          old_audit_class.where(auditable_type: model_class.name)
        end

        def convert_audit(old_audit, model_class)
          auditable_column = ActiveVersion.column_mapper.column_for(model_class, :audits, :auditable).to_s
          version_column = ActiveVersion.column_mapper.column_for(model_class, :audits, :version).to_s
          changes_column = ActiveVersion.column_mapper.column_for(model_class, :audits, :changes).to_s
          context_column = ActiveVersion.column_mapper.column_for(model_class, :audits, :context).to_s
          comment_column = ActiveVersion.column_mapper.column_for(model_class, :audits, :comment).to_s

          {
            "#{auditable_column}_id" => old_audit.auditable_id,
            "#{auditable_column}_type" => old_audit.auditable_type,
            version_column => old_audit.version,
            changes_column => old_audit.audited_changes,
            context_column => (old_audit.respond_to?(:audited_context) ? old_audit.audited_context : {}),
            comment_column => old_audit.comment,
            :created_at => old_audit.created_at,
            :updated_at => old_audit.updated_at || old_audit.created_at
          }
        end
      end
    end
  end
end
