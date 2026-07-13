module ActiveVersion
  # Instrumentation for ActiveSupport::Notifications
  module Instrumentation
    EVENTS = {
      translation_created: "translation_created.active_version",
      translation_updated: "translation_updated.active_version",
      translation_destroyed: "translation_destroyed.active_version",
      translation_fallback_used: "translation_fallback_used.active_version",
      revision_created: "revision.active_version",
      revision_reverted: "revision_reverted.active_version",
      revision_switch_applied: "revision_switch_applied.active_version",
      revision_write_failed: "revision_write_failed.active_version",
      audit_created: "audit.active_version",
      audit_write_failed: "audit_write_failed.active_version",
      audit_sql_generated: "audit_sql.active_version"
    }.freeze

    class << self
      # Instrument a translation creation
      def instrument_translation_created(translation, source)
        instrument_event(:translation_created) do
          {
            translation: translation,
            source: source,
            locale: translation.locale
          }
        end
      end

      # Instrument a translation update
      def instrument_translation_updated(translation, source)
        instrument_event(:translation_updated) do
          {
            translation: translation,
            source: source,
            locale: translation.locale
          }
        end
      end

      # Instrument a translation destroy
      def instrument_translation_destroyed(translation, source)
        instrument_event(:translation_destroyed) do
          {
            translation: translation,
            source: source,
            locale: translation.locale,
            translation_id: translation.id
          }
        end
      end

      # Instrument when translation falls back from requested locale
      def instrument_translation_fallback_used(source, attr:, requested_locale:, resolved_locale:)
        instrument_event(:translation_fallback_used) do
          {
            source: source,
            attr: attr,
            requested_locale: requested_locale,
            resolved_locale: resolved_locale
          }
        end
      end

      # Instrument a revision creation
      def instrument_revision_created(revision, source)
        source_class = source&.class
        source_class ||= revision.class.source_class if revision.class.respond_to?(:source_class)
        version_value = nil

        if source_class
          version_column = ActiveVersion.column_mapper.column_for(source_class, :revisions, :version)
          version_value = if revision.respond_to?(version_column)
            revision.public_send(version_column)
          else
            revision[version_column]
          end
        else
          version_value = revision[ActiveVersion.config.revision_version_column] if revision.respond_to?(:[])
          version_value ||= revision.version if revision.respond_to?(:version)
        end

        instrument_event(:revision_created) do
          {
            revision: revision,
            source: source,
            version: version_value
          }
        end
      rescue NameError
        instrument_event(:revision_created) do
          {
            revision: revision,
            source: source,
            version: nil
          }
        end
      end

      # Instrument revision revert action
      def instrument_revision_reverted(source, from_version:, to_version:, strategy: :revert_to)
        instrument_event(:revision_reverted) do
          {
            source: source,
            from_version: from_version,
            to_version: to_version,
            strategy: strategy
          }
        end
      end

      # Instrument revision pointer switch action
      def instrument_revision_switch_applied(source, from_version:, to_version:, append:)
        instrument_event(:revision_switch_applied) do
          {
            source: source,
            from_version: from_version,
            to_version: to_version,
            append: append
          }
        end
      end

      # Instrument revision write failures
      def instrument_revision_write_failed(source, error:)
        instrument_event(:revision_write_failed) do
          {
            source: source,
            error: format_error(error)
          }
        end
      end

      # Instrument an audit creation
      def instrument_audit_created(audit, auditable)
        source_class = auditable&.class
        source_class ||= audit.class.source_class if audit.class.respond_to?(:source_class)
        version_value = nil

        if source_class
          version_column = ActiveVersion.column_mapper.column_for(source_class, :audits, :version)
          version_value = if audit.respond_to?(version_column)
            audit.public_send(version_column)
          else
            audit[version_column]
          end
        else
          version_value = audit[ActiveVersion.config.audit_version_column] if audit.respond_to?(:[])
          version_value ||= audit.version if audit.respond_to?(:version)
        end

        instrument_event(:audit_created) do
          {
            audit: audit,
            auditable: auditable,
            action: audit.action,
            version: version_value
          }
        end
      rescue NameError
        instrument_event(:audit_created) do
          {
            audit: audit,
            auditable: auditable,
            action: audit.action,
            version: nil
          }
        end
      end

      # Instrument audit write failures
      def instrument_audit_write_failed(source, error:, action:)
        instrument_event(:audit_write_failed) do
          {
            source: source,
            action: action,
            error: format_error(error)
          }
        end
      end

      # Instrument SQL generation
      def instrument_audit_sql_generated(model, sql)
        instrument_event(:audit_sql_generated) do
          {
            model: model,
            sql: sql
          }
        end
      end

      private

      def instrument_event(event_key)
        event_name = EVENTS[event_key]
        return unless event_name
        return unless listening?(event_name)

        payload = block_given? ? yield : {}
        ActiveSupport::Notifications.instrument(event_name, payload)
      end

      def listening?(event_name)
        ActiveSupport::Notifications.notifier.listening?(event_name)
      rescue => e
        log_debug("listener probe failed for #{event_name}: #{e.class}: #{e.message}; assuming listeners may exist")
        true
      end

      def format_error(error)
        return nil if error.nil?

        {
          class: error.class.name,
          message: error.message
        }
      end

      def log_debug(message)
        ActiveVersion.log_debug("[ActiveVersion::Instrumentation] #{message}")
      end
    end
  end
end
