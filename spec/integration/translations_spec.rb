require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion Translations Integration", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    cleanup_test_data
    reset_active_version_context
  end

  describe "basic translation functionality" do
    it "creates default translation on post creation" do
      post = Post.create!(title: "Hello", body: "World")
      expect(post.translations.count).to eq(1)
      default_translation = post.translations.first
      expect(default_translation.locale).to eq("en")
      expect(default_translation.title).to eq("Hello")
    end

    it "allows creating additional translations" do
      post = Post.create!(title: "Hello")
      post.translations.create!(locale: "fi", title: "Hei", body: "Maailma")

      expect(post.translations.count).to eq(2)
      fi_translation = post.translations.find_by(locale: "fi")
      expect(fi_translation.title).to eq("Hei")
      expect(fi_translation.body).to eq("Maailma")
    end

    it "translates attributes by locale" do
      post = Post.create!(title: "Hello")
      post.translations.create!(locale: "fi", title: "Hei")

      expect(post.translate(:title, locale: "en")).to eq("Hello")
      expect(post.translate(:title, locale: "fi")).to eq("Hei")
      expect(post.translate(:title, locale: "sv")).to eq("Hello") # Fallback to default
    end

    it "returns translation record" do
      post = Post.create!(title: "Hello")
      post.translations.create!(locale: "fi", title: "Hei")

      translation = post.translation(locale: "fi")
      expect(translation).to be_a(PostTranslation)
      expect(translation.locale).to eq("fi")
      expect(translation.title).to eq("Hei")
    end
  end

  describe "translated scopes" do
    it "finds posts by translated title" do
      post1 = Post.create!(title: "Hello")
      post1.translations.create!(locale: "fi", title: "Hei")

      post2 = Post.create!(title: "World")
      post2.translations.create!(locale: "fi", title: "Maailma")

      results = Post.for_translated_title("Hei", locale: "fi")
      expect(results).to include(post1)
      expect(results).not_to include(post2)
    end
  end

  describe "translated copies" do
    it "copies translated values to source when blank" do
      post = Post.create!(title: nil, body: nil)
      # Use find_or_create to avoid unique constraint violation
      translation = post.translations.find_or_initialize_by(locale: "en")
      translation.title = "Hello"
      translation.body = "World"
      translation.save!
      post.reload
      post.valid? # Trigger before_validation callback

      expect(post.title).to eq("Hello")
      expect(post.body).to eq("World")
    end
  end
end
