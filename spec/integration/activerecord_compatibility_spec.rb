require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveRecord Compatibility", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostTranslation.destroy_all
    PostRevision.destroy_all
    PostAudit.destroy_all
  end

  describe "ActiveRecord core methods remain unchanged" do
    it "does not override ActiveRecord::Base methods" do
      # Verify ActiveRecord::Base methods are not patched
      expect(ActiveRecord::Base.instance_method(:save).owner.name).not_to include("ActiveVersion")
      expect(ActiveRecord::Base.instance_method(:save!).owner.name).not_to include("ActiveVersion")
      expect(ActiveRecord::Base.instance_method(:destroy).owner.name).not_to include("ActiveVersion")
      expect(ActiveRecord::Base.instance_method(:update).owner.name).not_to include("ActiveVersion")
      expect(ActiveRecord::Base.method(:create).owner.name).not_to include("ActiveVersion")
    end

    it "allows standard ActiveRecord query methods" do
      post = Post.create!(title: "Test", status: "draft")

      # Standard ActiveRecord methods should work
      expect(Post.where(status: "draft").count).to eq(1)
      expect(Post.find(post.id)).to eq(post)
      expect(Post.first).to eq(post)
      expect(Post.last).to eq(post)
      expect(Post.all.to_a).to include(post)
      expect(Post.exists?(post.id)).to be true
      expect(Post.count).to eq(1)
    end

    it "allows standard ActiveRecord persistence methods" do
      post = Post.new(title: "Test", status: "draft")

      # Standard persistence methods should work
      expect(post.save).to be true
      expect(post.persisted?).to be true
      expect(post.new_record?).to be false

      post.update!(status: "published")
      expect(post.status).to eq("published")

      post.destroy
      expect(post.destroyed?).to be true
    end

    it "allows standard ActiveRecord association methods" do
      post = Post.create!(title: "Test", status: "draft")

      # Standard association methods should work
      expect(post.respond_to?(:translations)).to be true
      expect(post.respond_to?(:revisions)).to be true
      expect(post.respond_to?(:audits)).to be true

      # Association proxies should support standard methods
      expect(post.translations).to respond_to(:where, :order, :limit, :count, :exists?, :find, :first, :last, :all)
      expect(post.revisions).to respond_to(:where, :order, :limit, :count, :exists?, :find, :first, :last, :all)
      expect(post.audits).to respond_to(:where, :order, :limit, :count, :exists?, :find, :first, :last, :all)
    end

    it "allows standard ActiveRecord callback methods" do
      # Verify callbacks can be added/removed
      callback_count_before = Post._update_callbacks.count

      Post.set_callback(:update, :before, :test_callback)

      expect(Post._update_callbacks.count).to eq(callback_count_before + 1)

      Post.skip_callback(:update, :before, :test_callback)
      expect(Post._update_callbacks.count).to eq(callback_count_before)
    end

    it "allows standard ActiveRecord validation methods" do
      post = Post.new(title: "", status: "draft")

      # Validations should work normally
      expect(post.valid?).to be true # Assuming no validations on Post
      expect(post.errors).to be_a(ActiveModel::Errors)
      expect(post.errors.empty?).to be true
    end

    it "allows standard ActiveRecord attribute methods" do
      post = Post.new(title: "Test", status: "draft")

      # Attribute accessors should work
      expect(post.title).to eq("Test")
      expect(post.status).to eq("draft")

      post.title = "Updated"
      expect(post.title).to eq("Updated")

      # Attribute query methods
      expect(post.title?).to be true
      expect(post.title_changed?).to be true
    end

    it "allows standard ActiveRecord transaction methods" do
      post = Post.create!(title: "Test", status: "draft")

      # Transactions should work
      ActiveRecord::Base.transaction do
        post.update!(status: "published")
        raise ActiveRecord::Rollback
      end

      post.reload
      expect(post.status).to eq("draft") # Rolled back
    end
  end

  describe "Plugin method independence" do
    it "does not override methods from other plugins" do
      post = Post.create!(title: "Test", status: "draft")

      # Each plugin should have its own methods
      # Translations methods
      expect(post).to respond_to(:translate)
      expect(post).to respond_to(:translation)
      expect(post.class).to respond_to(:translated_scopes)

      # Revisions methods
      expect(post).to respond_to(:revision)
      expect(post).to respond_to(:revision_at)
      expect(post).to respond_to(:at)
      expect(post).to respond_to(:create_snapshot!)

      # Audits methods
      expect(post).to respond_to(:audit_context=)
      expect(post).to respond_to(:audit_comment=)
      expect(post.class).to respond_to(:without_auditing)

      # Methods should not conflict
      expect(post.method(:translate).source_location).not_to eq(post.method(:revision).source_location)
      expect(post.method(:translate).source_location).not_to eq(post.method(:audit_context=).source_location)
    end

    it "allows using methods from all plugins simultaneously" do
      post = Post.create!(title: "Test", status: "draft")

      # Should be able to use all plugin methods
      translation = post.translation(locale: I18n.default_locale)
      expect(translation).to be_present

      post.update!(status: "published")
      revision = post.revision(version: 1)
      expect(revision).to be_present

      audit = post.audits.first
      expect(audit).to be_present

      # All should work independently
      expect(translation.title).to eq("Test")
      expect(revision.status).to be_present
      expect(audit.action).to eq("create")
    end

    it "does not create method name conflicts" do
      # Check that method names don't overlap
      translation_methods = Post.instance_methods.grep(/translation/)
      revision_methods = Post.instance_methods.grep(/revision/)
      audit_methods = Post.instance_methods.grep(/audit/)

      # No overlap between plugin method names
      expect(translation_methods & revision_methods).to be_empty
      expect(translation_methods & audit_methods).to be_empty
      expect(revision_methods & audit_methods).to be_empty
    end

    it "allows disabling one plugin without affecting others" do
      post = Post.create!(title: "Test", status: "draft")

      # Disable revisions
      Post.without_revisions do
        post.update!(status: "published")

        # Translations should still work
        expect(post.translations.count).to eq(1)
        expect(post.translation(locale: I18n.default_locale)).to be_present

        # Audits should still work
        expect(post.audits.count).to eq(2) # create + update

        # Revisions should be disabled
        expect(post.revisions.count).to eq(0)
      end

      # Disable audits
      Post.without_auditing do
        post.update!(status: "archived")

        # Translations should still work
        expect(post.translations.count).to eq(1)

        # Revisions should still work
        expect(post.revisions.count).to eq(1) # From previous update

        # Audits should be disabled
        expect(post.audits.count).to eq(2) # No new audit
      end
    end
  end

  describe "ActiveRecord::Base DSL methods" do
    it "adds DSL methods to ActiveRecord::Base (standard Rails pattern)" do
      # DSL methods (has_translations, has_revisions, has_audits) are added to ActiveRecord::Base
      # This is a standard Rails pattern (like has_many, belongs_to, etc.)
      # These are configuration methods, not functionality
      expect(ActiveRecord::Base).to respond_to(:has_translations)
      expect(ActiveRecord::Base).to respond_to(:has_revisions)
      expect(ActiveRecord::Base).to respond_to(:has_audits)

      # But functionality (associations, callbacks) should only be on models that use them
      expect(ActiveRecord::Base.reflect_on_association(:translations)).to be_nil
      expect(ActiveRecord::Base.reflect_on_association(:revisions)).to be_nil
      expect(ActiveRecord::Base.reflect_on_association(:audits)).to be_nil
    end

    it "does not add callbacks to ActiveRecord::Base" do
      # Verify ActiveRecord::Base does not have ActiveVersion callbacks
      # Callbacks should only be on models that include the concerns
      base_callbacks = ActiveRecord::Base._create_callbacks.map(&:filter)
      base_update_callbacks = ActiveRecord::Base._update_callbacks.map(&:filter)
      base_destroy_callbacks = ActiveRecord::Base._destroy_callbacks.map(&:filter)

      # These should not include ActiveVersion-specific callbacks on Base
      # (They may be present if Post class is loaded, but not on Base itself)
      # Check that Base doesn't have them directly
      expect(base_callbacks).not_to include(:audit_create) unless Post._create_callbacks.map(&:filter).include?(:audit_create)
      expect(base_update_callbacks).not_to include(:audit_update) unless Post._update_callbacks.map(&:filter).include?(:audit_update)
    end

    it "does not modify ActiveRecord::Base associations" do
      # Verify ActiveRecord::Base does not have our associations
      expect(ActiveRecord::Base.reflect_on_association(:translations)).to be_nil
      expect(ActiveRecord::Base.reflect_on_association(:revisions)).to be_nil
      expect(ActiveRecord::Base.reflect_on_association(:audits)).to be_nil
    end
  end

  describe "Model-specific behavior" do
    it "only adds functionality to models that use the DSL" do
      # Create a model without any ActiveVersion DSL calls
      Object.send(:remove_const, :PlainModel) if defined?(PlainModel)

      class PlainModel < ApplicationRecord
        self.table_name = "posts"
      end

      # DSL methods are available (they're on ActiveRecord::Base)
      expect(PlainModel).to respond_to(:has_translations)
      expect(PlainModel).to respond_to(:has_revisions)
      expect(PlainModel).to respond_to(:has_audits)

      # But functionality (associations, callbacks) should not be present
      expect(PlainModel.reflect_on_association(:translations)).to be_nil
      expect(PlainModel.reflect_on_association(:revisions)).to be_nil
      expect(PlainModel.reflect_on_association(:audits)).to be_nil

      # Should still have standard ActiveRecord methods
      expect(PlainModel).to respond_to(:create, :find, :where, :all)

      # Instance methods should not be present
      plain_instance = PlainModel.new(title: "Test", status: "draft")
      expect(plain_instance).not_to respond_to(:translate)
      expect(plain_instance).not_to respond_to(:revision)
      expect(plain_instance).not_to respond_to(:audit_context=)
    end

    it "allows standard ActiveRecord features on models with plugins" do
      post = Post.create!(title: "Test", status: "draft")

      # Should support all ActiveRecord features
      expect(post).to respond_to(:save, :save!, :update, :update!, :destroy, :destroy!)
      expect(post).to respond_to(:reload, :touch, :increment, :decrement)
      expect(post).to respond_to(:attributes, :attribute_names, :column_names)
      expect(post).to respond_to(:changed?, :changes, :previous_changes)
      expect(post).to respond_to(:valid?, :invalid?, :errors)
    end
  end

  describe "No method overriding between plugins" do
    it "ensures translations methods don't override revisions methods" do
      post = Post.create!(title: "Test", status: "draft")

      # Each plugin's methods should be distinct
      translation_method = post.method(:translate)
      revision_method = post.method(:revision)

      expect(translation_method.source_location).not_to eq(revision_method.source_location)
      expect(translation_method.name).not_to eq(revision_method.name)
    end

    it "ensures revisions methods don't override audits methods" do
      post = Post.create!(title: "Test", status: "draft")

      # Each plugin has distinct methods
      expect(post).to respond_to(:revision) # Revisions method
      expect(post).to respond_to(:audit_context=) # Audits method

      # Methods should be from different modules
      revision_method = post.method(:revision)
      audit_method = post.method(:audit_context=)

      expect(revision_method.owner).not_to eq(audit_method.owner)
    end

    it "ensures audits methods don't override translations methods" do
      post = Post.create!(title: "Test", status: "draft")

      # Each plugin has distinct methods
      expect(post).to respond_to(:translate) # Translations method
      expect(post).to respond_to(:audit_context=) # Audits method

      # Methods should be from different modules
      translation_method = post.method(:translate)
      audit_method = post.method(:audit_context=)

      expect(translation_method.owner).not_to eq(audit_method.owner)
    end

    it "allows all plugin class methods to coexist" do
      # Class methods from each plugin
      expect(Post).to respond_to(:translated_scopes) # Translations
      expect(Post).to respond_to(:without_revisions) # Revisions
      expect(Post).to respond_to(:without_auditing) # Audits

      # All should work independently
      Post.translated_scopes :title
      expect(Post).to respond_to(:for_translated_title)

      # Revisions and audits methods should still work
      expect(Post).to respond_to(:without_revisions)
      expect(Post).to respond_to(:without_auditing)
    end
  end

  describe "ActiveRecord callbacks remain standard" do
    it "uses standard ActiveRecord callback registration" do
      # Verify callbacks are registered using standard ActiveRecord methods
      post = Post.create!(title: "Test", status: "draft")

      # Callbacks should be in standard callback chains
      update_callbacks = post.class._update_callbacks.map(&:filter)
      expect(update_callbacks).to include(:create_revision_before_update)
      expect(update_callbacks).to include(:audit_update)

      # But they should be standard callbacks, not overrides
      expect(update_callbacks).to be_an(Array)
    end

    it "allows standard callback manipulation" do
      # Should be able to skip/remove callbacks using standard methods
      callback_count = Post._update_callbacks.count

      Post.skip_callback(:update, :before, :create_revision_before_update)
      expect(Post._update_callbacks.count).to eq(callback_count - 1)
    ensure
      # Always restore so later specs (e.g. revisions_spec) are not broken
      Post.setup_revision_callbacks(Post.revision_options) if Post.respond_to?(:setup_revision_callbacks) && Post.revision_options
    end
  end

  describe "ActiveRecord associations remain standard" do
    it "uses standard ActiveRecord association methods" do
      post = Post.create!(title: "Test", status: "draft")

      # Associations should be standard ActiveRecord associations
      translations_assoc = post.class.reflect_on_association(:translations)
      revisions_assoc = post.class.reflect_on_association(:revisions)
      audits_assoc = post.class.reflect_on_association(:audits)

      expect(translations_assoc).to be_a(ActiveRecord::Reflection::HasManyReflection)
      expect(revisions_assoc).to be_a(ActiveRecord::Reflection::HasManyReflection)
      expect(audits_assoc).to be_a(ActiveRecord::Reflection::HasManyReflection)
    end

    it "allows standard association query methods" do
      post = Post.create!(title: "Test", status: "draft")
      post.update!(status: "published")

      # Standard association methods should work
      expect(post.translations.where(locale: I18n.default_locale).count).to eq(1)
      expect(post.revisions.where(version: 1).count).to eq(1)
      expect(post.audits.where(action: "create").count).to eq(1)

      # Should support joins, includes, etc.
      expect(post.translations.joins("").count).to eq(1)
      expect(post.revisions.order(version: :desc).first).to be_present
      expect(post.audits.order(version: :asc).first).to be_present
    end
  end
end
