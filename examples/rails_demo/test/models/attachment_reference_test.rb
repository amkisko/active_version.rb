require "test_helper"
require "stringio"

class AttachmentReferenceTest < ActiveSupport::TestCase
  def uploaded_text(name, body)
    AttachmentUploader.upload(
      StringIO.new(body),
      :store,
      metadata: { "filename" => name, "mime_type" => "text/plain" }
    )
  end

  test "tracks attached file lifecycle for post records" do
    post = Post.create!(
      title: "Attachment tracking post",
      body: "Body",
      attachment: uploaded_text("first.txt", "first")
    )

    reference = AttachmentReference.find_by!(
      record_type: "Post",
      record_pk: post.id.to_s,
      attachment_name: "attachment"
    )

    assert_includes %w[cache store], reference.storage
    assert_equal "first.txt", reference.file_data["metadata"]["filename"]
    assert_nil reference.detached_at

    post.update!(attachment: uploaded_text("second.txt", "second"))
    reference.reload

    assert_equal "second.txt", reference.file_data["metadata"]["filename"]
    assert_nil reference.detached_at

    post.destroy!
    reference.reload

    assert_not_nil reference.detached_at
  end
end
