require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Concerns", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  describe "HasAudits concern" do
    let(:model_class) do
      audit_class_ref = PostAudit
      Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "TestPost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: audit_class_ref
      end
    end

    it "adds audits association" do
      expect(model_class.new).to respond_to(:audits)
    end

    it "adds audit_revision method" do
      expect(model_class.new).to respond_to(:audit_revision)
    end

    it "adds audit_revision_at method" do
      expect(model_class.new).to respond_to(:audit_revision_at)
    end

    it "adds audit_comment accessor" do
      instance = model_class.new
      instance.audit_comment = "Test comment"
      expect(instance.audit_comment).to eq("Test comment")
    end

    it "adds audit_context accessor" do
      instance = model_class.new
      instance.audit_context = {ip: "127.0.0.1"}
      expect(instance.audit_context).to eq({ip: "127.0.0.1"})
    end

    it "supports only option" do
      audit_class_ref = PostAudit
      model_with_only = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "PostWithOnly"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: audit_class_ref, only: [:title]
      end

      expect(model_with_only.audited_options[:only]).to include("title")
    end

    it "supports except option" do
      audit_class_ref = PostAudit
      model_with_except = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "PostWithExcept"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: audit_class_ref, except: [:body]
      end

      expect(model_with_except.audited_options[:except]).to include("body")
    end

    it "supports if condition" do
      audit_class_ref = PostAudit
      model_with_if = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "PostWithIf"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: audit_class_ref, if: :should_audit?

        def should_audit?
          true
        end
      end

      expect(model_with_if.audited_options[:if]).to eq(:should_audit?)
    end

    it "supports unless condition" do
      audit_class_ref = PostAudit
      model_with_unless = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "PostWithUnless"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: audit_class_ref, unless: :skip_audit?

        def skip_audit?
          false
        end
      end

      expect(model_with_unless.audited_options[:unless]).to eq(:skip_audit?)
    end

    it "supports associated_with option" do
      audit_class_ref = PostAudit
      model_with_associated = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "PostWithAssociated"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: audit_class_ref, associated_with: :user
      end

      expect(model_with_associated.audit_associated_with).to eq(:user)
    end

    it "supports comment_required option" do
      audit_class_ref = PostAudit
      model_with_required = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "PostWithRequired"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: audit_class_ref, comment_required: true
      end

      expect(model_with_required.audited_options[:comment_required]).to be true
    end
  end

  describe "HasRevisions concern" do
    let(:model_class) do
      Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "TestPost"
        end

        include ActiveVersion::Revisions::HasRevisions

        has_revisions
      end
    end

    it "adds revisions association" do
      expect(model_class.new).to respond_to(:revisions)
    end

    it "adds revision method" do
      expect(model_class.new).to respond_to(:revision)
    end

    it "adds revision_at method" do
      expect(model_class.new).to respond_to(:revision_at)
    end

    it "adds current_version method" do
      expect(model_class.new).to respond_to(:current_version)
    end

    it "adds create_snapshot! method" do
      expect(model_class.new).to respond_to(:create_snapshot!)
    end

    it "adds revert_to method" do
      expect(model_class.new).to respond_to(:revert_to)
    end

    it "adds versions enumerator" do
      expect(model_class.new).to respond_to(:versions)
    end
  end

  describe "HasTranslations concern" do
    let(:model_class) do
      Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "TestPost"
        end

        include ActiveVersion::Translations::HasTranslations

        has_translations
      end
    end

    it "adds translations association" do
      expect(model_class.new).to respond_to(:translations)
    end

    it "adds translated_scopes class method" do
      expect(model_class).to respond_to(:translated_scopes)
    end

    it "adds translated_copies class method" do
      expect(model_class).to respond_to(:translated_copies)
    end

    it "supports translated_scopes" do
      model_with_scopes = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "PostWithScopes"
        end

        include ActiveVersion::Translations::HasTranslations

        has_translations
        translated_scopes :title
      end

      expect(model_with_scopes).to respond_to(:for_translated_title)
    end

    it "supports translated_copies" do
      model_with_copies = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "PostWithCopies"
        end

        include ActiveVersion::Translations::HasTranslations

        has_translations
        translated_copies :title, :body
      end

      # translated_copies sets up before_validation callbacks
      expect(model_with_copies).to be_a(Class)
    end
  end

  describe "multiple concerns together" do
    let(:model_class) do
      Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "FullPost"
        end

        include ActiveVersion::Translations::HasTranslations
        include ActiveVersion::Revisions::HasRevisions
        include ActiveVersion::Audits::HasAudits

        has_translations
        has_revisions
        has_audits as: "PostAudit"
      end
    end

    it "works with all concerns included" do
      instance = model_class.new

      expect(instance).to respond_to(:audits)
      expect(instance).to respond_to(:revisions)
      expect(instance).to respond_to(:translations)
    end

    it "does not have method conflicts" do
      instance = model_class.new

      # revision method should come from HasRevisions (or its submodules)
      revision_owner = instance.method(:revision).owner
      expect(revision_owner).to be_a(Module)
      expect(revision_owner.name).to start_with("ActiveVersion::Revisions::HasRevisions")

      # audit_revision method should come from HasAudits
      expect(instance.method(:audit_revision).owner).to eq(ActiveVersion::Audits::HasAudits)
    end
  end
end
