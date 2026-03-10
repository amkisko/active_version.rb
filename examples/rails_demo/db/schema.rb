# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 17) do
  create_table "admin_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "attachment_references", force: :cascade do |t|
    t.string "attachment_name", default: "attachment", null: false
    t.datetime "created_at", null: false
    t.datetime "detached_at"
    t.json "file_data"
    t.string "file_id"
    t.datetime "last_seen_at", null: false
    t.string "record_pk", null: false
    t.string "record_type", null: false
    t.string "storage"
    t.datetime "updated_at", null: false
    t.index ["detached_at"], name: "index_attachment_references_on_detached_at"
    t.index ["record_type", "record_pk", "attachment_name"], name: "index_attachment_references_on_record_and_name", unique: true
    t.index ["storage", "file_id"], name: "index_attachment_references_on_storage_and_file_id"
  end

  create_table "audits", force: :cascade do |t|
    t.string "action", null: false
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "auditable_id", null: false
    t.string "auditable_type", null: false
    t.json "audited_changes", default: {}, null: false
    t.json "audited_context", default: {}
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "user_type"
    t.integer "version", null: false
    t.index ["associated_type", "associated_id"], name: "index_audits_on_associated"
    t.index ["auditable_type", "auditable_id", "version"], name: "index_audits_on_auditable_and_version", unique: true
    t.index ["auditable_type", "auditable_id"], name: "index_audits_on_auditable"
    t.index ["auditable_type", "auditable_id"], name: "index_audits_on_auditable_type_and_auditable_id"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_type", "user_id"], name: "index_audits_on_user"
    t.index ["user_type", "user_id"], name: "index_audits_on_user_type_and_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "column_post_audits", force: :cascade do |t|
    t.string "action", null: false
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "auditable_id", null: false
    t.string "auditable_type", null: false
    t.json "audited_context", default: {}
    t.text "comment"
    t.datetime "created_at", null: false
    t.boolean "published"
    t.string "remote_address"
    t.string "request_uuid"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "user_type"
    t.integer "version", null: false
    t.index ["associated_type", "associated_id"], name: "index_column_post_audits_on_associated"
    t.index ["auditable_type", "auditable_id", "version"], name: "index_column_post_audits_on_auditable_and_version", unique: true
    t.index ["auditable_type", "auditable_id"], name: "index_column_post_audits_on_auditable"
    t.index ["auditable_type", "auditable_id"], name: "index_column_post_audits_on_auditable_type_and_auditable_id"
    t.index ["published"], name: "index_column_post_audits_on_published"
    t.index ["request_uuid"], name: "index_column_post_audits_on_request_uuid"
    t.index ["title"], name: "index_column_post_audits_on_title"
    t.index ["user_type", "user_id"], name: "index_column_post_audits_on_user"
  end

  create_table "column_posts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.text "internal_notes"
    t.boolean "published", default: false, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
  end

  create_table "composite_demo_audits", id: false, force: :cascade do |t|
    t.integer "audit_id", null: false
    t.integer "auditable_id", null: false
    t.string "auditable_type", null: false
    t.json "audited_changes", default: {}, null: false
    t.string "comment"
    t.datetime "created_at", null: false
    t.date "partition_key", null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["audit_id", "partition_key"], name: "index_composite_demo_audits_on_pk", unique: true
    t.index ["auditable_type", "auditable_id", "version", "partition_key"], name: "index_composite_demo_audits_on_logical_and_partition", unique: true
    t.index ["partition_key"], name: "index_composite_demo_audits_on_partition_key"
  end

  create_table "issue_revisions", force: :cascade do |t|
    t.integer "assignee_id"
    t.text "attachment_data"
    t.integer "author_id"
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "issue_id", null: false
    t.json "labels_json", default: [], null: false
    t.string "status", default: "open", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["issue_id", "version"], name: "index_issue_revisions_on_issue_id_and_version", unique: true
    t.index ["issue_id"], name: "index_issue_revisions_on_issue_id"
  end

  create_table "issue_translations", force: :cascade do |t|
    t.text "attachment_data"
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "issue_id", null: false
    t.json "labels_json", default: [], null: false
    t.string "locale", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["issue_id", "locale"], name: "index_issue_translations_on_issue_id_and_locale", unique: true
    t.index ["issue_id"], name: "index_issue_translations_on_issue_id"
    t.index ["locale"], name: "index_issue_translations_on_locale"
  end

  create_table "issues", force: :cascade do |t|
    t.integer "assignee_id"
    t.text "attachment_data"
    t.integer "author_id"
    t.text "body"
    t.datetime "created_at", null: false
    t.json "labels_json", default: [], null: false
    t.string "status", default: "open", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_issues_on_assignee_id"
    t.index ["author_id"], name: "index_issues_on_author_id"
  end

  create_table "post_audits", force: :cascade do |t|
    t.string "action", null: false
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "auditable_id", null: false
    t.string "auditable_type", null: false
    t.json "audited_changes", default: {}, null: false
    t.json "audited_context", default: {}
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "user_type"
    t.integer "version", null: false
    t.index ["associated_type", "associated_id"], name: "index_post_audits_on_associated"
    t.index ["auditable_type", "auditable_id", "version"], name: "index_post_audits_on_auditable_and_version", unique: true
    t.index ["auditable_type", "auditable_id"], name: "index_post_audits_on_auditable"
    t.index ["auditable_type", "auditable_id"], name: "index_post_audits_on_auditable_type_and_auditable_id"
    t.index ["request_uuid"], name: "index_post_audits_on_request_uuid"
    t.index ["user_type", "user_id"], name: "index_post_audits_on_user"
    t.index ["user_type", "user_id"], name: "index_post_audits_on_user_type_and_user_id"
  end

  create_table "post_revisions", force: :cascade do |t|
    t.integer "assignee_id"
    t.text "attachment_data"
    t.text "body"
    t.datetime "created_at", null: false
    t.json "flex_store", default: {}, null: false
    t.json "labels_json", default: [], null: false
    t.integer "post_id", null: false
    t.decimal "price", precision: 12, scale: 4
    t.datetime "published_at"
    t.json "settings_json", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["post_id", "version"], name: "index_post_revisions_on_post_id_and_version", unique: true
    t.index ["post_id"], name: "index_post_revisions_on_post_id"
  end

  create_table "post_translations", force: :cascade do |t|
    t.text "attachment_data"
    t.text "body"
    t.datetime "created_at", null: false
    t.json "flex_store", default: {}, null: false
    t.json "labels_json", default: [], null: false
    t.string "locale", null: false
    t.integer "post_id", null: false
    t.json "settings_json", default: {}, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["locale"], name: "index_post_translations_on_locale"
    t.index ["post_id", "locale"], name: "index_post_translations_on_post_id_and_locale", unique: true
    t.index ["post_id"], name: "index_post_translations_on_post_id"
  end

  create_table "posts", force: :cascade do |t|
    t.integer "assignee_id"
    t.text "attachment_data"
    t.integer "author_id"
    t.text "body"
    t.integer "category_id"
    t.datetime "created_at", null: false
    t.json "flex_store", default: {}, null: false
    t.json "labels_json", default: [], null: false
    t.decimal "price", precision: 12, scale: 4
    t.datetime "published_at"
    t.json "settings_json", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_posts_on_assignee_id"
    t.index ["author_id"], name: "index_posts_on_author_id"
    t.index ["category_id"], name: "index_posts_on_category_id"
  end

  create_table "pull_request_revisions", force: :cascade do |t|
    t.integer "assignee_id"
    t.text "attachment_data"
    t.integer "author_id"
    t.text "body"
    t.datetime "created_at", null: false
    t.json "labels_json", default: [], null: false
    t.integer "pull_request_id", null: false
    t.string "source_branch"
    t.string "status", default: "open", null: false
    t.string "target_branch"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["pull_request_id", "version"], name: "index_pull_request_revisions_on_pr_id_and_version", unique: true
    t.index ["pull_request_id"], name: "index_pull_request_revisions_on_pull_request_id"
  end

  create_table "pull_request_translations", force: :cascade do |t|
    t.text "attachment_data"
    t.text "body"
    t.datetime "created_at", null: false
    t.json "labels_json", default: [], null: false
    t.string "locale", null: false
    t.integer "pull_request_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["locale"], name: "index_pull_request_translations_on_locale"
    t.index ["pull_request_id", "locale"], name: "index_pull_request_translations_on_pr_id_and_locale", unique: true
    t.index ["pull_request_id"], name: "index_pull_request_translations_on_pull_request_id"
  end

  create_table "pull_requests", force: :cascade do |t|
    t.integer "assignee_id"
    t.text "attachment_data"
    t.integer "author_id"
    t.text "body"
    t.datetime "created_at", null: false
    t.json "labels_json", default: [], null: false
    t.string "source_branch", default: "feature", null: false
    t.string "status", default: "open", null: false
    t.string "target_branch", default: "main", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_pull_requests_on_assignee_id"
    t.index ["author_id"], name: "index_pull_requests_on_author_id"
  end

  create_table "source_identity_post_audits", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "auditable_id", null: false
    t.string "auditable_type", null: false
    t.json "audited_changes", default: {}, null: false
    t.json "audited_context", default: {}
    t.string "comment"
    t.datetime "created_at", null: false
    t.date "partition_key", null: false
    t.string "source_key", null: false
    t.string "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["auditable_type", "auditable_id", "version", "partition_key"], name: "index_source_identity_post_audits_on_logical_and_partition", unique: true
    t.index ["tenant_id", "source_key", "partition_key"], name: "index_source_identity_post_audits_on_business_key"
  end

  create_table "source_identity_post_revisions", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.date "partition_key", null: false
    t.integer "source_identity_post_id", null: false
    t.string "source_key", null: false
    t.string "status"
    t.string "tenant_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["source_identity_post_id", "version", "partition_key"], name: "index_source_identity_post_revisions_on_src_version_partition", unique: true
    t.index ["source_identity_post_id"], name: "idx_on_source_identity_post_id_be9f43eafa"
  end

  create_table "source_identity_post_translations", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "locale", null: false
    t.date "partition_key", null: false
    t.integer "source_identity_post_id", null: false
    t.string "source_key", null: false
    t.string "status"
    t.string "tenant_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["source_identity_post_id", "locale", "partition_key"], name: "index_source_identity_post_translations_on_src_locale_partition", unique: true
    t.index ["source_identity_post_id"], name: "idx_on_source_identity_post_id_306172ee7b"
  end

  create_table "source_identity_posts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.date "partition_key", null: false
    t.string "source_key", null: false
    t.string "status", default: "draft", null: false
    t.string "tenant_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "source_key", "partition_key"], name: "index_source_identity_posts_on_business_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "issue_revisions", "issues"
  add_foreign_key "issue_translations", "issues"
  add_foreign_key "issues", "users", column: "assignee_id"
  add_foreign_key "issues", "users", column: "author_id"
  add_foreign_key "post_revisions", "posts"
  add_foreign_key "post_translations", "posts"
  add_foreign_key "posts", "categories"
  add_foreign_key "posts", "users", column: "assignee_id"
  add_foreign_key "posts", "users", column: "author_id"
  add_foreign_key "pull_request_revisions", "pull_requests"
  add_foreign_key "pull_request_translations", "pull_requests"
  add_foreign_key "pull_requests", "users", column: "assignee_id"
  add_foreign_key "pull_requests", "users", column: "author_id"
  add_foreign_key "source_identity_post_revisions", "source_identity_posts"
  add_foreign_key "source_identity_post_translations", "source_identity_posts"
end
