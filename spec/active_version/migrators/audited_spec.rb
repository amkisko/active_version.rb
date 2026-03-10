require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe ActiveVersion::Migrators::Audited do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  describe ".migrate" do
    context "when model has audited gem support" do
      let(:model_class) do
        Class.new(ApplicationRecord) do
          self.table_name = "posts"
          def self.name
            "Post"
          end

          def self.audited?
            true
          end

          def self.audit_class
            PostAudit
          end
        end
      end

      context "with dry_run option" do
        it "returns count without actually migrating" do
          # Create some fake old audits
          old_audit = double("old_audit",
            auditable_id: 1,
            auditable_type: "Post",
            version: 1,
            audited_changes: {"title" => "Hello"},
            comment: "Test",
            created_at: Time.current,
            updated_at: Time.current)

          allow(described_class).to receive(:source_audits).and_return([old_audit])
          allow(described_class).to receive(:create_audit)

          count = described_class.migrate(model_class, dry_run: true)

          expect(count).to eq(1)
          expect(described_class).not_to have_received(:create_audit)
        end
      end

      context "without dry_run option" do
        it "migrates audits from audited gem" do
          old_audit = double("old_audit",
            auditable_id: 1,
            auditable_type: "Post",
            version: 1,
            audited_changes: {"title" => "Hello"},
            comment: "Test",
            created_at: Time.current,
            updated_at: Time.current,
            respond_to?: true)

          allow(old_audit).to receive(:respond_to?).with(:audited_context).and_return(false)

          allow(described_class).to receive_messages(source_audits: [old_audit], create_audit: true)

          count = described_class.migrate(model_class, dry_run: false)

          expect(count).to eq(1)
          expect(described_class).to have_received(:create_audit).once
        end
      end

      context "when old audit has audited_context" do
        it "includes audited_context in migration" do
          old_audit = double("old_audit",
            auditable_id: 1,
            auditable_type: "Post",
            version: 1,
            audited_changes: {"title" => "Hello"},
            audited_context: {"ip" => "127.0.0.1"},
            comment: "Test",
            created_at: Time.current,
            updated_at: Time.current,
            respond_to?: true)

          allow(old_audit).to receive(:respond_to?).with(:audited_context).and_return(true)

          allow(described_class).to receive_messages(source_audits: [old_audit], create_audit: true)

          count = described_class.migrate(model_class, dry_run: false)

          expect(count).to eq(1)
          expect(described_class).to have_received(:create_audit).once
        end
      end
    end

    context "when model does not have audited gem support" do
      let(:model_class) do
        Class.new(ApplicationRecord) do
          self.table_name = "posts"
          def self.name
            "Post"
          end
        end
      end

      it "returns 0" do
        count = described_class.migrate(model_class)
        expect(count).to eq(0)
      end
    end

    context "when audit_class is nil" do
      let(:model_class) do
        Class.new(ApplicationRecord) do
          self.table_name = "posts"
          def self.name
            "Post"
          end

          def self.audited?
            true
          end

          def self.audit_class
            nil
          end
        end
      end

      it "returns 0" do
        count = described_class.migrate(model_class)
        expect(count).to eq(0)
      end
    end
  end

  describe ".convert_audit" do
    let(:model_class) { Post }
    let(:old_audit) do
      double("old_audit",
        auditable_id: 1,
        auditable_type: "Post",
        version: 2,
        audited_changes: {"title" => ["Old", "New"]},
        comment: "Updated",
        created_at: Time.current,
        updated_at: Time.current,
        respond_to?: false)
    end

    it "converts old audit to new format" do
      result = described_class.send(:convert_audit, old_audit, model_class)

      expect(result["auditable_id"]).to eq(1)
      expect(result["auditable_type"]).to eq("Post")
      expect(result["version"]).to eq(2)
      expect(result["audited_changes"]).to eq({"title" => ["Old", "New"]})
      expect(result["comment"]).to eq("Updated")
      expect(result[:created_at]).to be_a(Time)
      expect(result[:updated_at]).to be_a(Time)
    end

    context "when updated_at is nil" do
      let(:old_audit) do
        double("old_audit",
          auditable_id: 1,
          auditable_type: "Post",
          version: 2,
          audited_changes: {"title" => ["Old", "New"]},
          comment: "Updated",
          created_at: Time.current,
          updated_at: nil,
          respond_to?: false)
      end

      it "uses created_at for updated_at" do
        result = described_class.send(:convert_audit, old_audit, model_class)

        expect(result[:updated_at]).to eq(result[:created_at])
      end
    end
  end
end
