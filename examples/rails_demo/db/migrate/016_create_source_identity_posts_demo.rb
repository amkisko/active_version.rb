class CreateSourceIdentityPostsDemo < ActiveRecord::Migration[8.0]
  def change
    create_table :source_identity_posts do |t|
      t.string :tenant_id, null: false
      t.string :source_key, null: false
      t.date :partition_key, null: false
      t.string :title, null: false
      t.text :body
      t.string :status, null: false, default: "draft"
      t.timestamps
    end

    add_index :source_identity_posts,
              [:tenant_id, :source_key, :partition_key],
              unique: true,
              name: "index_source_identity_posts_on_business_key"

    create_table :source_identity_post_translations do |t|
      t.references :source_identity_post, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :tenant_id, null: false
      t.string :source_key, null: false
      t.date :partition_key, null: false
      t.string :title
      t.text :body
      t.string :status
      t.timestamps
    end

    add_index :source_identity_post_translations,
              [:source_identity_post_id, :locale, :partition_key],
              unique: true,
              name: "index_source_identity_post_translations_on_src_locale_partition"

    create_table :source_identity_post_revisions do |t|
      t.references :source_identity_post, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :tenant_id, null: false
      t.string :source_key, null: false
      t.date :partition_key, null: false
      t.string :title
      t.text :body
      t.string :status
      t.timestamps
    end

    add_index :source_identity_post_revisions,
              [:source_identity_post_id, :version, :partition_key],
              unique: true,
              name: "index_source_identity_post_revisions_on_src_version_partition"

    create_table :source_identity_post_audits do |t|
      t.string :auditable_type, null: false
      t.bigint :auditable_id, null: false
      t.string :action, null: false
      t.integer :version, null: false
      t.string :tenant_id, null: false
      t.string :source_key, null: false
      t.date :partition_key, null: false
      t.string :comment
      t.json :audited_changes, null: false, default: {}
      t.json :audited_context, default: {}
      t.timestamps
    end

    add_index :source_identity_post_audits,
              [:auditable_type, :auditable_id, :version, :partition_key],
              unique: true,
              name: "index_source_identity_post_audits_on_logical_and_partition"
    add_index :source_identity_post_audits,
              [:tenant_id, :source_key, :partition_key],
              name: "index_source_identity_post_audits_on_business_key"
  end
end
