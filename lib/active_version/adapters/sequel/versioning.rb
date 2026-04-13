require "json"
require "active_support/core_ext/string/inflections"

module ActiveVersion
  module Adapters
    module Sequel
      # Sequel plugin that provides ActiveVersion-style model DSL and lifecycle hooks.
      module Versioning
        DEFAULT_CONFIG = {
          revision_model: nil,
          audit_model: nil,
          translation_model: nil,
          foreign_key: nil,
          tracked_columns: [],
          translation_columns: []
        }.freeze

        def self.apply(model, **options)
          configure(model, **options)
        end

        def self.configure(model, **options)
          base = model.instance_variable_get(:@active_version_sequel_config) || {}
          model.instance_variable_set(:@active_version_sequel_config, DEFAULT_CONFIG.merge(base).merge(options))
        end

        module ClassMethods
          def active_version(**options)
            ActiveVersion::Adapters::Sequel::Versioning.configure(self, **options)
          end

          def active_version_config
            config = instance_variable_get(:@active_version_sequel_config)
            return config if config

            if superclass.respond_to?(:active_version_config)
              superclass.active_version_config.dup
            else
              ActiveVersion::Adapters::Sequel::Versioning::DEFAULT_CONFIG.dup
            end
          end

          def has_versioning?(version_type)
            case version_type.to_sym
            when :revisions then !active_version_config[:revision_model].nil?
            when :audits then !active_version_config[:audit_model].nil?
            when :translations then !active_version_config[:translation_model].nil?
            else false
            end
          end
        end

        module InstanceMethods
          def active_version_foreign_key
            self.class.active_version_config[:foreign_key] || :"#{model_name.singularize}_id"
          end

          def active_version_tracked_columns
            self.class.active_version_config[:tracked_columns].map(&:to_sym)
          end

          def active_version_translation_columns
            columns = self.class.active_version_config[:translation_columns]
            columns = active_version_tracked_columns if columns.nil? || columns.empty?
            columns.map(&:to_sym)
          end

          def active_version_revisions_dataset
            model = self.class.active_version_config[:revision_model]
            return nil unless model

            model.where(active_version_foreign_key => pk)
          end

          def active_version_audits_dataset
            model = self.class.active_version_config[:audit_model]
            return nil unless model

            model.where(active_version_foreign_key => pk)
          end

          def active_version_translations_dataset
            model = self.class.active_version_config[:translation_model]
            return nil unless model

            model.where(active_version_foreign_key => pk)
          end

          def active_version_revisions
            dataset = active_version_revisions_dataset
            return [] unless dataset

            dataset.order(:version).all
          end

          def active_version_audits
            dataset = active_version_audits_dataset
            return [] unless dataset

            dataset.order(:version).all
          end

          def active_version_translations
            dataset = active_version_translations_dataset
            return [] unless dataset

            dataset.order(:locale).all
          end

          def active_version_translation(locale)
            dataset = active_version_translations_dataset
            return nil unless dataset

            dataset.where(locale: locale.to_s.downcase).first
          end

          def active_version_translate(attr, locale:)
            translation = active_version_translation(locale)
            return self[attr] unless translation

            translated_value = translation[attr]
            (translated_value.nil? || translated_value.to_s.empty?) ? self[attr] : translated_value
          end

          def active_version_set_translation!(locale:, **attrs)
            locale_value = locale.to_s.downcase
            model = self.class.active_version_config[:translation_model]
            raise ActiveVersion::ConfigurationError, "translation_model is not configured for #{self.class.name}" unless model

            payload = attrs.transform_keys(&:to_sym).slice(*active_version_translation_columns)
            existing = active_version_translation(locale_value)

            if existing
              existing.update(payload)
              ActiveVersion::Instrumentation.instrument_translation_updated(existing, self)
              existing
            else
              created = model.create(payload.merge(active_version_foreign_key => pk, :locale => locale_value))
              ActiveVersion::Instrumentation.instrument_translation_created(created, self)
              created
            end
          end

          def active_version_destroy_translation!(locale:)
            translation = active_version_translation(locale)
            return false unless translation

            ActiveVersion::Instrumentation.instrument_translation_destroyed(translation, self)
            translation.delete
            true
          end

          def before_update
            @active_version_previous_snapshot = active_version_previous_snapshot_from_db
            super
          end

          def before_destroy
            @active_version_previous_snapshot = active_version_snapshot
            super
          end

          def after_create
            super
            active_version_create_revision_and_audit!(:create, previous_snapshot: nil)
          end

          def after_update
            super
            active_version_create_revision_and_audit!(:update, previous_snapshot: @active_version_previous_snapshot)
            @active_version_previous_snapshot = nil
          end

          def after_destroy
            super
            active_version_create_destroy_audit!(@active_version_previous_snapshot)
          ensure
            @active_version_previous_snapshot = nil
          end

          private

          def pk
            self[self.class.primary_key]
          end

          def model_name
            self.class.name.split("::").last.downcase
          end

          def active_version_snapshot
            active_version_tracked_columns.each_with_object({}) do |column, out|
              out[column] = self[column]
            end
          end

          def active_version_previous_snapshot_from_db
            persisted = self.class.where(self.class.primary_key => pk).first
            return active_version_snapshot unless persisted

            active_version_tracked_columns.each_with_object({}) do |column, out|
              out[column] = persisted[column]
            end
          end

          def active_version_change_set(previous_snapshot)
            current = active_version_snapshot
            previous = previous_snapshot || Hash.new(nil)
            current.each_with_object({}) do |(column, value), out|
              old_value = previous[column]
              next if old_value == value

              out[column.to_s] = [old_value, value]
            end
          end

          def active_version_next_version
            max_revision = active_version_revisions_dataset&.max(:version) || 0
            max_audit = active_version_audits_dataset&.max(:version) || 0
            [max_revision, max_audit].max + 1
          end

          def active_version_create_revision_and_audit!(action, previous_snapshot:)
            change_set = active_version_change_set(previous_snapshot)
            return if action.to_s == "update" && change_set.empty?

            version = active_version_next_version
            active_version_insert_revision!(version)
            active_version_insert_audit!(action: action, version: version, changes: change_set)
          end

          def active_version_create_destroy_audit!(previous_snapshot)
            return unless self.class.active_version_config[:audit_model]

            previous = previous_snapshot || active_version_snapshot
            change_set = previous.each_with_object({}) do |(column, value), out|
              out[column.to_s] = [value, nil]
            end
            version = active_version_next_version
            active_version_insert_audit!(action: "destroy", version: version, changes: change_set)
          end

          def active_version_insert_revision!(version)
            revision_model = self.class.active_version_config[:revision_model]
            return unless revision_model

            payload = active_version_snapshot.merge(
              active_version_foreign_key => pk,
              :version => version
            )

            revision = revision_model.create(payload)
            ActiveVersion::Instrumentation.instrument_revision_created(revision, self)
            revision
          rescue => e
            ActiveVersion::Instrumentation.instrument_revision_write_failed(self, error: e)
            raise
          end

          def active_version_insert_audit!(action:, version:, changes:)
            audit_model = self.class.active_version_config[:audit_model]
            return unless audit_model

            payload = {
              active_version_foreign_key => pk,
              :version => version,
              :action => action,
              :audited_changes => JSON.generate(changes),
              :audited_context => JSON.generate(ActiveVersion.context || {})
            }

            audit = audit_model.create(payload)
            ActiveVersion::Instrumentation.instrument_audit_created(audit, self)
            audit
          rescue => e
            ActiveVersion::Instrumentation.instrument_audit_write_failed(self, error: e, action: action)
            raise
          end
        end
      end
    end
  end
end
