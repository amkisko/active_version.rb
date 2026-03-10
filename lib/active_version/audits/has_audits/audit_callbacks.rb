module ActiveVersion
  module Audits
    module HasAudits
      # Callback methods for audit creation
      module AuditCallbacks
        extend ActiveSupport::Concern

        private

        def audit_create
          write_audit(action: "create", audited_changes: audited_attributes,
            comment: audit_comment, context: audit_context)
        end

        def audit_update
          # Use audited_changes method (like audited gem) - this runs in before_update
          # This matches the audited gem pattern - capture changes BEFORE they're saved
          changes = audited_changes(exclude_readonly_attrs: true)

          # Skip if no changes and no comment (unless update_with_comment_only is true)
          # Match audited gem behavior: only skip if changes are empty AND comment is blank
          return if changes.empty? && (audit_comment.blank? || audited_options[:update_with_comment_only] == false)

          # Capture audit_context before it might be cleared
          # Use the accessor method which reads @audit_context
          write_audit(action: "update", audited_changes: changes,
            comment: audit_comment, context: audit_context)
        end

        def audit_touch
          unless (changes = audited_changes(for_touch: true, exclude_readonly_attrs: true)).empty?
            write_audit(action: "update", audited_changes: changes,
              comment: audit_comment)
          end
        end

        def audit_destroy
          unless new_record?
            write_audit(action: "destroy", audited_changes: audited_attributes,
              comment: audit_comment)
          end
        end
      end
    end
  end
end
