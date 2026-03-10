require "test_helper"

class ColumnPostTest < ActiveSupport::TestCase
  test "stores audited fields directly in audit columns without audited_changes column" do
    post = ColumnPost.create!(
      title: "v1",
      body: "Body",
      internal_notes: "Private note",
      published: false
    )

    assert_not_includes ColumnPostAudit.column_names, "audited_changes"
    assert_equal 1, post.audits.count
    assert_equal "v1", post.audits.last.title
    assert_equal false, post.audits.last.published
  end

  test "tracks only configured columns and supports filtering by audit columns" do
    post = ColumnPost.create!(title: "Audit Me", body: "Body", internal_notes: "v1", published: false)
    initial_count = post.audits.count

    post.update!(internal_notes: "v2")
    assert_equal initial_count, post.audits.count

    post.update!(title: "Audit Me v2", published: true)
    latest = post.audits.reorder(version: :desc).first

    assert_equal "Audit Me v2", latest.title
    assert_equal true, latest.published
    assert ColumnPostAudit.where(auditable: post).with_title("Audit Me v2").exists?
    assert ColumnPostAudit.published_only.exists?
  end
end
