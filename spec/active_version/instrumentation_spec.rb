require "spec_helper"

RSpec.describe ActiveVersion::Instrumentation do
  before do
    allow(ActiveSupport::Notifications.notifier).to receive(:listening?).and_return(true)
  end

  describe ".instrument_translation_created" do
    it "instruments translation creation" do
      translation = double("translation", locale: "en")
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "translation_created.active_version",
        {
          translation: translation,
          source: :test,
          locale: "en"
        }
      )
      described_class.instrument_translation_created(translation, :test)
    end
  end

  describe ".instrument_translation_updated" do
    it "instruments translation update" do
      translation = double("translation", locale: "en")
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "translation_updated.active_version",
        {
          translation: translation,
          source: :test,
          locale: "en"
        }
      )
      described_class.instrument_translation_updated(translation, :test)
    end
  end

  describe ".instrument_translation_destroyed" do
    it "instruments translation destroy" do
      translation = double("translation", locale: "en", id: 12)
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "translation_destroyed.active_version",
        {
          translation: translation,
          source: :test,
          locale: "en",
          translation_id: 12
        }
      )
      described_class.instrument_translation_destroyed(translation, :test)
    end
  end

  describe ".instrument_translation_fallback_used" do
    it "instruments translation fallback usage" do
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "translation_fallback_used.active_version",
        {
          source: :source,
          attr: :title,
          requested_locale: :de,
          resolved_locale: :en
        }
      )
      described_class.instrument_translation_fallback_used(
        :source,
        attr: :title,
        requested_locale: :de,
        resolved_locale: :en
      )
    end
  end

  describe ".instrument_revision_created" do
    it "instruments revision creation" do
      revision = double("revision", version: 1)
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "revision.active_version",
        {
          revision: revision,
          source: :test,
          version: 1
        }
      )
      described_class.instrument_revision_created(revision, :test)
    end

    it "falls back to hash/index readers when source is nil" do
      revision = double("revision")
      allow(revision).to receive(:class).and_return(Class.new)
      allow(revision).to receive(:respond_to?) { |method_name, *_args| method_name == :[] || method_name == :version }
      allow(revision).to receive(:[]).and_return(9)
      allow(revision).to receive(:version).and_return(10)

      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "revision.active_version",
        hash_including(version: 9)
      )

      described_class.instrument_revision_created(revision, nil)
    end

    it "emits nil version when revision version lookup raises NameError" do
      revision = double("revision", version: 1)
      source = :source
      allow(ActiveVersion.column_mapper).to receive(:column_for).and_raise(NameError)

      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "revision.active_version",
        hash_including(version: nil, source: source)
      )

      described_class.instrument_revision_created(revision, source)
    end
  end

  describe ".instrument_revision_reverted" do
    it "instruments revision revert" do
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "revision_reverted.active_version",
        {
          source: :source,
          from_version: 7,
          to_version: 3,
          strategy: :revert_to
        }
      )
      described_class.instrument_revision_reverted(:source, from_version: 7, to_version: 3)
    end
  end

  describe ".instrument_revision_switch_applied" do
    it "instruments revision switch" do
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "revision_switch_applied.active_version",
        {
          source: :source,
          from_version: 7,
          to_version: 6,
          append: true
        }
      )
      described_class.instrument_revision_switch_applied(:source, from_version: 7, to_version: 6, append: true)
    end
  end

  describe ".instrument_revision_write_failed" do
    it "instruments revision write failures" do
      error = RuntimeError.new("boom")
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "revision_write_failed.active_version",
        {
          source: :source,
          error: {class: "RuntimeError", message: "boom"}
        }
      )
      described_class.instrument_revision_write_failed(:source, error: error)
    end
  end

  describe ".instrument_audit_created" do
    it "instruments audit creation" do
      audit = double("audit", action: "create", version: 1)
      auditable = double("auditable")
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "audit.active_version",
        {
          audit: audit,
          auditable: auditable,
          action: "create",
          version: 1
        }
      )
      described_class.instrument_audit_created(audit, auditable)
    end

    it "falls back to hash/index readers when auditable is nil" do
      audit = double("audit")
      allow(audit).to receive(:class).and_return(Class.new)
      allow(audit).to receive(:respond_to?) { |method_name, *_args| method_name == :[] }
      allow(audit).to receive(:[]).and_return(11)
      allow(audit).to receive(:version).and_return(12)
      allow(audit).to receive(:action).and_return("update")

      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "audit.active_version",
        hash_including(version: 11, action: "update")
      )

      described_class.instrument_audit_created(audit, nil)
    end

    it "emits nil version when audit version lookup raises NameError" do
      audit = double("audit", action: "create")
      auditable = :auditable
      allow(ActiveVersion.column_mapper).to receive(:column_for).and_raise(NameError)

      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "audit.active_version",
        hash_including(version: nil, auditable: auditable)
      )

      described_class.instrument_audit_created(audit, auditable)
    end
  end

  describe ".instrument_audit_write_failed" do
    it "instruments audit write failures" do
      error = RuntimeError.new("bad insert")
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "audit_write_failed.active_version",
        {
          source: :source,
          action: "update",
          error: {class: "RuntimeError", message: "bad insert"}
        }
      )
      described_class.instrument_audit_write_failed(:source, error: error, action: "update")
    end
  end

  describe ".instrument_audit_sql_generated" do
    it "instruments SQL generation" do
      model = double("model")
      sql = "INSERT INTO audits..."
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "audit_sql.active_version",
        {
          model: model,
          sql: sql
        }
      )
      described_class.instrument_audit_sql_generated(model, sql)
    end
  end

  describe "performance guard" do
    it "does not instrument when event has no listeners" do
      allow(ActiveSupport::Notifications.notifier).to receive(:listening?).and_return(false)
      expect(ActiveSupport::Notifications).not_to receive(:instrument)
      described_class.instrument_translation_created(double("translation", locale: "en"), :source)
    end

    it "instruments when listening? probe raises (fail-open)" do
      allow(ActiveSupport::Notifications.notifier).to receive(:listening?).and_raise(StandardError, "boom")
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "translation_created.active_version",
        hash_including(locale: "en")
      )

      described_class.instrument_translation_created(double("translation", locale: "en"), :source)
    end
  end
end
