require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Callback Control", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostRevision.destroy_all
    PostAudit.destroy_all
  end

  describe "Revision callback control" do
    it "allows disabling automatic callbacks with auto: false" do
      # Create a simple class that only has revisions
      manual_post_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "ManualRevisionPost"
        end

        include ActiveVersion::Revisions::HasRevisions

        # Override revision_class to use PostRevision
        def self.revision_class
          PostRevision
        end
      end

      # Set up the association manually to use PostRevision
      manual_post_class.has_many :revisions, class_name: "PostRevision", foreign_key: "post_id", dependent: :delete_all

      manual_post_class.has_revisions auto: false

      # Manually install callback
      manual_post_class.revision_on_update

      post = manual_post_class.create!(title: "v1")
      post.title = "v2"
      post.save!

      expect(post.revisions.count).to eq(1)
    end

    it "allows custom if condition" do
      # Use PostRevision for simplicity
      conditional_post_class = Class.new(Post) do
        def self.name
          "ConditionalRevisionPost"
        end

        # Override to use PostRevision
        def self.revision_class
          PostRevision
        end

        # Override to use PostTranslation since this subclass doesn't have its own translation class
        def self.translation_class
          PostTranslation
        end
      end

      conditional_post_class.has_revisions if: :should_revision?

      conditional_post_class.class_eval do
        attr_accessor :revision_enabled
        def should_revision?
          revision_enabled == true
        end
      end

      post = conditional_post_class.create!(title: "v1")
      post.revision_enabled = false
      post.title = "v2"
      post.save!
      expect(post.revisions.count).to eq(0)

      post.revision_enabled = true
      post.title = "v3"
      post.save!
      expect(post.revisions.count).to eq(1)
    end

    it "allows custom unless condition" do
      # Use PostRevision for simplicity
      conditional_post_class = Class.new(Post) do
        def self.name
          "UnlessRevisionPost"
        end

        # Override to use PostRevision
        def self.revision_class
          PostRevision
        end

        # Override to use PostTranslation since this subclass doesn't have its own translation class
        def self.translation_class
          PostTranslation
        end
      end

      conditional_post_class.has_revisions unless: :skip_revision?

      conditional_post_class.class_eval do
        attr_accessor :skip_revision
        def skip_revision?
          skip_revision == true
        end
      end

      post = conditional_post_class.create!(title: "v1")
      post.skip_revision = true
      post.title = "v2"
      post.save!
      expect(post.revisions.count).to eq(0)

      post.skip_revision = false
      post.title = "v3"
      post.save!
      expect(post.revisions.count).to eq(1)
    end

    it "allows on: [] to disable automatic callbacks" do
      # Use PostRevision for simplicity
      manual_post_class = Class.new(Post) do
        def self.name
          "ManualOnPost"
        end

        # Override to use PostRevision
        def self.revision_class
          PostRevision
        end

        # Override to use PostTranslation since this subclass doesn't have its own translation class
        def self.translation_class
          PostTranslation
        end
      end

      manual_post_class.has_revisions on: []

      # Manually install callback
      manual_post_class.revision_on_update

      post = manual_post_class.create!(title: "v1")
      post.title = "v2"
      post.save!

      expect(post.revisions.count).to eq(1)
    end

    it "does not raise in switch_to! when callbacks are manual (auto: false)" do
      manual_post_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "ManualSwitchRevisionPost"
        end

        include ActiveVersion::Revisions::HasRevisions

        has_revisions as: PostRevision, auto: false
        has_many :revisions, class_name: "PostRevision", foreign_key: "post_id", dependent: :delete_all
        revision_on_update
      end

      post = manual_post_class.create!(title: "v1")
      post.update!(title: "v2")
      post.update!(title: "v3")

      expect { post.switch_to!(1) }.not_to raise_error
      expect(post.title).to eq("v1")
    end
  end

  describe "Audit callback control" do
    it "allows disabling automatic callbacks with auto: false" do
      manual_post_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "ManualAuditPost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: PostAudit, auto: false

        # Manually install callbacks
        audit_on_create
        audit_on_update
      end

      post = manual_post_class.create!(title: "v1")
      expect(post.audits.count).to eq(1)

      post.title = "v2"
      post.save!
      expect(post.audits.count).to eq(2)
    end

    it "allows custom if condition" do
      conditional_post_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "ConditionalAuditPost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: PostAudit, if: :should_audit?

        attr_accessor :audit_enabled
        def should_audit?
          audit_enabled != false
        end
      end

      post = conditional_post_class.create!(title: "v1")
      post.audit_enabled = false
      post.title = "v2"
      post.save!
      expect(post.audits.count).to eq(1) # Only create audit

      post.audit_enabled = true
      post.title = "v3"
      post.save!
      expect(post.audits.count).to eq(2) # Create + update audits
    end

    it "allows custom unless condition" do
      conditional_post_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "UnlessAuditPost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: PostAudit, unless: :skip_audit?

        attr_accessor :skip_audit
        def skip_audit?
          skip_audit == true
        end
      end

      post = conditional_post_class.create!(title: "v1")
      post.skip_audit = true
      post.title = "v2"
      post.save!
      expect(post.audits.count).to eq(1) # Only create audit

      post.skip_audit = false
      post.title = "v3"
      post.save!
      expect(post.audits.count).to eq(2) # Create + update audits
    end

    it "allows on: [] to disable automatic callbacks" do
      manual_post_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "ManualOnAuditPost"
        end

        include ActiveVersion::Audits::HasAudits

        has_audits as: PostAudit, on: []

        # Manually install callbacks
        audit_on_create
        audit_on_update
      end

      post = manual_post_class.create!(title: "v1")
      expect(post.audits.count).to eq(1)

      post.title = "v2"
      post.save!
      expect(post.audits.count).to eq(2)
    end
  end

  describe "Combined conditions" do
    it "allows combining if and unless conditions" do
      combined_post_class = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        def self.name
          "CombinedPost"
        end

        include ActiveVersion::Revisions::HasRevisions
        include ActiveVersion::Audits::HasAudits

        has_revisions as: PostRevision, if: :revision_enabled?, unless: :skip_revision?
        has_audits as: PostAudit, if: :audit_enabled?, unless: :skip_audit?

        # Manually fix the association since it was set up before has_revisions was called
        _reflections.delete(:revisions)
        has_many :revisions,
          class_name: "PostRevision",
          inverse_of: :post,
          dependent: :delete_all

        attr_accessor :revision_enabled, :skip_revision, :audit_enabled, :skip_audit

        def revision_enabled?
          revision_enabled == true
        end

        def skip_revision?
          skip_revision == true
        end

        def audit_enabled?
          audit_enabled == true
        end

        def skip_audit?
          skip_audit == true
        end
      end

      post = combined_post_class.new(title: "v1")
      post.revision_enabled = true
      post.audit_enabled = true
      post.skip_revision = false
      post.skip_audit = false
      post.save!

      post.title = "v2"
      post.save!
      expect(post.revisions.count).to eq(1)
      expect(post.audits.count).to eq(2) # create + update
    end
  end
end
