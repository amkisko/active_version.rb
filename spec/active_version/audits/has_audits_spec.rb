require "spec_helper"

RSpec.describe ActiveVersion::Audits::HasAudits do
  let(:model_class) do
    Class.new(ApplicationRecord) do
      include ActiveVersion::Audits::HasAudits

      self.table_name = "posts"
      def self.name
        "Post"
      end
    end
  end

  describe ".audit_record?" do
    it "returns false" do
      expect(model_class.audit_record?).to be false
    end
  end

  describe ".audit_class" do
    it "returns nil when audit class doesn't exist" do
      expect(model_class.audit_class).to be_nil
    end
  end

  describe ".has_audits" do
    it "defines has_audits class method" do
      expect(model_class).to respond_to(:has_audits)
    end
  end

  describe ".without_auditing" do
    it "defines without_auditing class method" do
      expect(model_class).to respond_to(:without_auditing)
    end
  end

  describe "#audit_sql" do
    let(:instance) { model_class.new(title: "Hello") }

    it "responds to audit_sql method" do
      expect(instance).to respond_to(:audit_sql)
    end
  end

  describe "#audit_revision" do
    let(:instance) { model_class.new }

    it "responds to audit_revision method" do
      expect(instance).to respond_to(:audit_revision)
    end
  end

  describe "#audit_revision_at" do
    let(:instance) { model_class.new }

    it "responds to audit_revision_at method" do
      expect(instance).to respond_to(:audit_revision_at)
    end
  end

  describe "#own_and_associated_audits" do
    let(:instance) { model_class.new }

    it "responds to own_and_associated_audits method" do
      expect(instance).to respond_to(:own_and_associated_audits)
    end
  end

  describe "#without_auditing" do
    let(:instance) { model_class.new }

    it "responds to without_auditing method" do
      expect(instance).to respond_to(:without_auditing)
    end
  end
end
