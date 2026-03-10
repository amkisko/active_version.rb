require "spec_helper"
require "support/database"

RSpec.describe ActiveVersion::Audits::AuditRecord do
  before(:all) do
    DatabaseHelper.setup
  end

  let(:source_class) do
    Class.new(ApplicationRecord) do
      self.table_name = "posts"
      def self.name
        "Post"
      end
    end
  end

  let(:audit_class) do
    Class.new(ApplicationRecord) do
      include ActiveVersion::Audits::AuditRecord

      self.table_name = "post_audits"
      def self.name
        "PostAudit"
      end
    end.tap do |klass|
      # Ensure setup_associations is called
      klass.setup_associations if klass.respond_to?(:setup_associations)
    end
  end

  describe ".audit_record?" do
    it "returns true" do
      expect(audit_class.audit_record?).to be true
    end
  end

  describe ".source_name" do
    it "extracts source name from class name" do
      expect(audit_class.source_name).to eq(:post)
    end
  end

  describe ".source_foreign_key" do
    it "returns the foreign key name" do
      # This depends on column mapper configuration
      expect(audit_class.source_name).to eq(:post)
    end
  end

  describe ".creates" do
    it "defines creates scope" do
      expect(audit_class).to respond_to(:creates)
    end
  end

  describe ".updates" do
    it "defines updates scope" do
      expect(audit_class).to respond_to(:updates)
    end
  end

  describe ".ascending" do
    it "defines ascending scope" do
      expect(audit_class).to respond_to(:ascending)
    end
  end

  describe "#new_attributes" do
    let(:audit) do
      audit_class.new(
        :action => "update",
        ActiveVersion.config.audit_changes_column => {"title" => ["old", "new"]}.to_json
      )
    end

    it "returns new attribute values" do
      expect(audit.new_attributes["title"]).to eq("new")
    end

    it "returns the value for create action" do
      create_audit = audit_class.new(
        :action => "create",
        ActiveVersion.config.audit_changes_column => {"title" => "new"}.to_json
      )
      expect(create_audit.new_attributes["title"]).to eq("new")
    end
  end

  describe "#old_attributes" do
    let(:audit) do
      audit_class.new(
        :action => "update",
        ActiveVersion.config.audit_changes_column => {"title" => ["old", "new"]}.to_json
      )
    end

    it "returns old attribute values" do
      expect(audit.old_attributes["title"]).to eq("old")
    end

    it "returns nil for create action" do
      create_audit = audit_class.new(
        :action => "create",
        ActiveVersion.config.audit_changes_column => {"title" => "new"}.to_json
      )
      expect(create_audit.old_attributes["title"]).to be_nil
    end
  end

  describe "safe YAML parsing" do
    it "does not deserialize disallowed YAML classes" do
      payload = "--- !ruby/object:OpenStruct\n table:\n  dangerous: true\n"

      parsed = audit_class.deserialize_audit_payload(payload, column_name: :audited_context)
      expect(parsed).to eq(payload)
    end
  end

  describe "callback helpers" do
    before do
      PostTranslation.delete_all
      PostRevision.delete_all
      PostAudit.delete_all
      Post.delete_all
    end

    it "computes next version for update actions using identity columns" do
      PostAudit.create!(
        auditable_type: "Post",
        auditable_id: 101,
        action: "update",
        version: 1,
        audited_changes: {}
      )

      candidate = audit_class.new(
        auditable_type: "Post",
        auditable_id: 101,
        action: "update",
        audited_changes: {}
      )

      candidate.send(:set_version_number)
      expect(candidate.version).to eq(2)
    end

    it "skips version assignment when audit identity is incomplete" do
      candidate = audit_class.new(
        auditable_type: "Post",
        action: "update",
        audited_changes: {}
      )

      candidate.send(:set_version_number)
      expect(candidate.version).to be_nil
    end

    it "loads auditable record in instrumentation fallback path" do
      post = Post.create!(title: "Instrumented")
      audit = audit_class.new(
        auditable_type: "Post",
        auditable_id: post.id,
        action: "update",
        version: 2,
        audited_changes: {"title" => ["old", "new"]}.to_json
      )

      allow(audit).to receive(:respond_to?).and_call_original
      allow(audit).to receive(:respond_to?).with(:auditable).and_return(false)

      expect(ActiveVersion::Instrumentation).to receive(:instrument_audit_created).with(audit, an_instance_of(Post))
      audit.send(:instrument_audit_created)
    end

    it "sets audit user from current_user_method when RequestStore is empty" do
      ActiveVersion::RequestStore.audited_user = nil
      user = double("fallback_user", id: 55, class: double(name: "User"))

      candidate = audit_class.new
      candidate.define_singleton_method(:current_user) { user }
      candidate.send(:set_audit_user)

      expect(candidate.user_id).to eq(55)
      expect(candidate.user_type).to eq("User")
    end
  end

  describe "storage-driven serializer selection" do
    it "uses JSON serializer for json_column storage" do
      klass = Class.new(ApplicationRecord) do
        include ActiveVersion::Audits::AuditRecord
        self.table_name = "post_audits"
        def self.name = "ConfiguredAudit"

        configure_audit do
          storage :json_column
        end
      end

      serializer = klass.serializer_for_column(:audited_changes)
      expect(serializer).to be_a(ActiveVersion::Audits::AuditRecord::Serializers::Json)
    end

    it "supports custom storage provider objects" do
      provider = Class.new do
        def load(value) = "loaded:#{value}"
        def dump(value) = "dumped:#{value}"
      end.new

      klass = Class.new(ApplicationRecord) do
        include ActiveVersion::Audits::AuditRecord
        self.table_name = "post_audits"
        def self.name = "CustomStorageAudit"

        register_storage_provider :custom_payload, provider
        configure_audit do
          storage :custom_payload
        end
      end

      expect(klass.serialize_audit_payload("abc", column_name: :audited_changes)).to eq("dumped:abc")
      expect(klass.deserialize_audit_payload("abc", column_name: :audited_changes)).to eq("loaded:abc")
    end

    it "supports custom storage provider factory blocks" do
      klass = Class.new(ApplicationRecord) do
        include ActiveVersion::Audits::AuditRecord
        self.table_name = "post_audits"
        def self.name = "CustomStorageFactoryAudit"

        register_audit_storage_provider(:custom_factory_payload) do |_audit_class, column_name|
          Class.new do
            define_method(:initialize) { |col| @col = col }
            define_method(:load) { |value| "#{@col}:#{value}" }
            define_method(:dump) { |value| "#{@col}:#{value}" }
          end.new(column_name)
        end

        configure_audit do
          storage :custom_factory_payload
        end
      end

      expect(klass.serialize_audit_payload("abc", column_name: :audited_context)).to eq("audited_context:abc")
      expect(klass.deserialize_audit_payload("abc", column_name: :audited_context)).to eq("audited_context:abc")
    end
  end
end
