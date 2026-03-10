require "spec_helper"

RSpec.describe ActiveVersion::Adapters::Sequel::Versioning do
  class SequelSpecRow
    def initialize(attrs = {})
      @attrs = attrs.transform_keys(&:to_sym)
    end

    def [](key)
      @attrs[key.to_sym]
    end

    def []=(key, value)
      @attrs[key.to_sym] = value
    end

    def update(payload)
      payload.each { |k, v| self[k] = v }
      self
    end

    def delete
      @deleted = true
    end

    def method_missing(name, *args, &block)
      return self[name] if args.empty? && @attrs.key?(name.to_sym)
      super
    end

    def respond_to_missing?(name, include_private = false)
      @attrs.key?(name.to_sym) || super
    end
  end

  class SequelSpecDataset
    def initialize(rows)
      @rows = rows
    end

    def where(filters)
      filtered = @rows.select do |row|
        filters.all? { |k, v| row.public_send(k) == v }
      end
      self.class.new(filtered)
    end

    def order(column)
      self.class.new(@rows.sort_by { |row| row.public_send(column) })
    end

    def all
      @rows
    end

    def first
      @rows.first
    end

    def max(column)
      values = @rows.map { |row| row.public_send(column) }.compact
      values.max
    end
  end

  class SequelSpecStore
    class << self
      attr_accessor :rows
    end
    self.rows = []

    def self.reset!
      self.rows = []
    end

    def self.where(filters)
      SequelSpecDataset.new(rows).where(filters)
    end

    def self.create(payload)
      row = SequelSpecRow.new(payload)
      rows << row
      row
    end
  end

  let(:model_class) do
    base_class = Class.new do
      def before_update
        :base_before_update
      end

      def before_destroy
        :base_before_destroy
      end

      def after_create
        :base_after_create
      end

      def after_update
        :base_after_update
      end

      def after_destroy
        :base_after_destroy
      end
    end

    Class.new(base_class) do
      extend ActiveVersion::Adapters::Sequel::Versioning::ClassMethods
      include ActiveVersion::Adapters::Sequel::Versioning::InstanceMethods

      def self.name
        "SequelSpecModel"
      end

      def self.primary_key
        :id
      end

      def self.where(filters)
        id = filters.fetch(:id)
        SequelSpecDataset.new(@rows || []).where(id: id)
      end

      def self.set_rows(rows)
        @rows = rows
      end

      def initialize(attrs = {})
        @attrs = attrs
      end

      def [](key)
        @attrs[key]
      end

      def []=(key, value)
        @attrs[key] = value
      end

      def update(attrs)
        attrs.each { |k, v| @attrs[k] = v }
        self
      end

      def delete
        @deleted = true
      end

      def deleted?
        @deleted == true
      end
    end
  end

  let(:instance) { model_class.new(id: 10, title: "hello", body: "world") }

  before do
    SequelSpecStore.reset!
    model_class.set_rows([SequelSpecRow.new(id: 10, title: "persisted", body: "persisted-body")])
    ActiveVersion::Adapters::Sequel::Versioning.configure(
      model_class,
      foreign_key: :record_id,
      tracked_columns: %i[title body],
      translation_columns: [:title],
      revision_model: SequelSpecStore,
      audit_model: SequelSpecStore,
      translation_model: SequelSpecStore
    )
  end

  it "applies and configures model options" do
    klass = Class.new do
      extend ActiveVersion::Adapters::Sequel::Versioning::ClassMethods

      def self.name
        "AppliedSequelModel"
      end
    end
    described_class.apply(klass, foreign_key: :custom_id)
    expect(klass.active_version_config[:foreign_key]).to eq(:custom_id)
  end

  it "supports class DSL and versioning checks" do
    expect(model_class.has_versioning?(:revisions)).to eq(true)
    expect(model_class.has_versioning?(:audits)).to eq(true)
    expect(model_class.has_versioning?(:translations)).to eq(true)
    expect(model_class.has_versioning?(:unknown)).to eq(false)
  end

  it "returns foreign key and configured columns" do
    expect(instance.active_version_foreign_key).to eq(:record_id)
    expect(instance.active_version_tracked_columns).to eq(%i[title body])
    expect(instance.active_version_translation_columns).to eq([:title])
  end

  it "falls back translation columns to tracked columns" do
    ActiveVersion::Adapters::Sequel::Versioning.configure(model_class, translation_columns: [])
    expect(instance.active_version_translation_columns).to eq(%i[title body])
  end

  it "returns ordered datasets and translation lookup" do
    SequelSpecStore.create(record_id: 10, version: 2, locale: "fi", title: "Moi")
    SequelSpecStore.create(record_id: 10, version: 1, locale: "en", title: "Hello")

    expect(instance.active_version_revisions.length).to eq(2)
    expect(instance.active_version_audits.length).to eq(2)
    expect(instance.active_version_translations.map(&:locale)).to eq(%w[en fi])
    expect(instance.active_version_translation("FI").title).to eq("Moi")
    expect(instance.active_version_translate(:title, locale: "fi")).to eq("Moi")
    expect(instance.active_version_translate(:body, locale: "fi")).to eq("world")
  end

  it "creates and updates translations with instrumentation" do
    expect(ActiveVersion::Instrumentation).to receive(:instrument_translation_created)
    created = instance.active_version_set_translation!(locale: :en, title: "Hello", ignored: "x")
    expect(created.title).to eq("Hello")

    expect(ActiveVersion::Instrumentation).to receive(:instrument_translation_updated)
    updated = instance.active_version_set_translation!(locale: :en, title: "Hello 2")
    expect(updated.title).to eq("Hello 2")
  end

  it "destroys translations with instrumentation" do
    instance.active_version_set_translation!(locale: :en, title: "Hello")
    expect(ActiveVersion::Instrumentation).to receive(:instrument_translation_destroyed)
    expect(instance.active_version_destroy_translation!(locale: :en)).to eq(true)
    expect(instance.active_version_destroy_translation!(locale: :missing)).to eq(false)
  end

  it "raises when translation model is missing" do
    ActiveVersion::Adapters::Sequel::Versioning.configure(model_class, translation_model: nil)
    expect {
      instance.active_version_set_translation!(locale: :en, title: "Hello")
    }.to raise_error(ActiveVersion::ConfigurationError, /translation_model is not configured/)
  end

  it "captures snapshots and change sets" do
    current = instance.send(:active_version_snapshot)
    previous = instance.send(:active_version_previous_snapshot_from_db)
    expect(current).to eq(title: "hello", body: "world")
    expect(previous).to eq(title: "persisted", body: "persisted-body")

    changes = instance.send(:active_version_change_set, {title: "old", body: "world"})
    expect(changes).to eq("title" => ["old", "hello"])
  end

  it "computes next version from revision/audit datasets" do
    SequelSpecStore.create(record_id: 10, version: 4)
    SequelSpecStore.create(record_id: 10, version: 7)
    expect(instance.send(:active_version_next_version)).to eq(8)
  end

  it "creates revision and audit payloads with instrumentation" do
    allow(ActiveVersion).to receive(:context).and_return({"request_id" => "abc"})
    expect(ActiveVersion::Instrumentation).to receive(:instrument_revision_created)
    expect(ActiveVersion::Instrumentation).to receive(:instrument_audit_created)

    revision = instance.send(:active_version_insert_revision!, 3)
    audit = instance.send(:active_version_insert_audit!, action: "update", version: 3, changes: {"title" => ["a", "b"]})

    expect(revision.version).to eq(3)
    expect(audit.action).to eq("update")
  end

  it "instruments and re-raises revision/audit write failures" do
    failing_model = Class.new do
      def self.where(_filters) = SequelSpecDataset.new([])
      def self.create(_payload) = raise(StandardError, "boom")
    end

    ActiveVersion::Adapters::Sequel::Versioning.configure(
      model_class,
      revision_model: failing_model,
      audit_model: failing_model
    )

    expect(ActiveVersion::Instrumentation).to receive(:instrument_revision_write_failed)
    expect {
      instance.send(:active_version_insert_revision!, 1)
    }.to raise_error(StandardError, "boom")

    expect(ActiveVersion::Instrumentation).to receive(:instrument_audit_write_failed)
    expect {
      instance.send(:active_version_insert_audit!, action: "update", version: 1, changes: {})
    }.to raise_error(StandardError, "boom")
  end

  it "runs lifecycle hooks and cleans previous snapshot state" do
    expect(instance.before_update).to eq(:base_before_update)
    expect(instance.before_destroy).to eq(:base_before_destroy)

    expect(ActiveVersion::Instrumentation).to receive(:instrument_revision_created).at_least(:once)
    expect(ActiveVersion::Instrumentation).to receive(:instrument_audit_created).at_least(:once)
    expect { instance.after_create }.not_to raise_error
    expect { instance.after_update }.not_to raise_error

    expect { instance.after_destroy }.not_to raise_error
  end
end
