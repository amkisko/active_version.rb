require "test_helper"
require "stringio"
require "bigdecimal"

class PostTest < ActiveSupport::TestCase
  def uploaded_text(name, body)
    AttachmentUploader.upload(
      StringIO.new(body),
      :store,
      metadata: { "filename" => name, "mime_type" => "text/plain" }
    )
  end

  test "requires title" do
    post = Post.new(body: "Body only")

    assert_not post.valid?
    assert_includes post.errors[:title], "can't be blank"
  end

  test "can be created without category and author" do
    post = Post.new(title: "Hello")

    assert post.save
  end

  test "belongs to category and author when provided" do
    user = User.create!(name: "Author", email: "author@example.com", password: "password")
    category = Category.create!(name: "Tech")
    post = Post.create!(title: "Hello", body: "World", category: category, author: user)

    assert_equal category, post.category
    assert_equal user, post.author
  end

  test "supports attachment on post and translation with revision snapshots" do
    post = Post.create!(
      title: "With file",
      body: "Body",
      attachment: uploaded_text("source.txt", "source")
    )

    assert post.attachment.present?
    assert_equal "source.txt", post.attachment.original_filename

    translation = post.translations.create!(
      locale: "fi",
      title: "Tiedosto",
      body: "Runko",
      attachment: uploaded_text("fi.txt", "suomi")
    )

    assert translation.attachment.present?
    assert_equal "fi.txt", translation.attachment.original_filename

    post.update!(
      title: "With file v2",
      attachment: uploaded_text("source-v2.txt", "source v2")
    )

    latest_revision = post.revisions.order(version: :desc).first
    assert latest_revision.attachment.present?
    assert_equal "source-v2.txt", latest_revision.attachment.original_filename
  end

  test "tracks json fields, scalar complex fields, and virtual attributes in revisions and audits" do
    previous_debounce = ActiveVersion.config.debounce_time
    ActiveVersion.config.debounce_time = nil

    post = Post.create!(
      title: "Complex",
      body: "Field demo",
      status: "draft",
      price: BigDecimal("10.2500"),
      published_at: Time.current
    )

    post.seo_title = "SEO Complex"
    post.keywords_csv = "rails, audit, revision"
    post.runtime_note = "ephemeral only"
    post.save!

    post.seo_title = "SEO Complex v2"
    post.keywords_csv = "rails, audit, revision, json"
    post.update!(
      status: "published",
      price: BigDecimal("11.7500"),
      published_at: Time.current + 1.hour,
      body: "Field demo updated"
    )

    post.reload
    assert_equal "SEO Complex v2", post.seo_title
    assert_equal "rails, audit, revision, json", post.keywords_csv
    assert_equal "published", post.status

    latest_revision = post.revisions.reorder(version: :desc).first
    # Revisions are pre-update snapshots, so they keep previous values.
    assert_equal "draft", latest_revision.status
    assert_equal "10.25", latest_revision.price.to_s
    assert_equal "SEO Complex", latest_revision.seo_title
    assert_equal "rails, audit, revision", latest_revision.keywords_csv

    latest_audit = post.audits.reorder(version: :desc).first
    assert latest_audit.audited_changes.key?("status")
    assert latest_audit.audited_changes.key?("price")
    assert latest_audit.audited_changes.key?("settings_json")
    assert latest_audit.audited_changes.key?("flex_store")
  ensure
    ActiveVersion.config.debounce_time = previous_debounce
  end
end
