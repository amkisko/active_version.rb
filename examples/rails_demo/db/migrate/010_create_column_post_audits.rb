class CreateColumnPostAudits < ActiveRecord::Migration[7.0]
  def change
    create_table :column_post_audits do |t|
      t.references :auditable, polymorphic: true, null: false
      t.references :user, polymorphic: true
      t.references :associated, polymorphic: true
      t.string :action, null: false
      t.integer :version, null: false
      t.text :comment
      t.json :audited_context, default: {}
      t.string :request_uuid
      t.string :remote_address

      # Audited fields stored directly as columns (no audited_changes JSON column).
      t.string :title
      t.boolean :published

      t.timestamps
    end

    add_index :column_post_audits, [:auditable_type, :auditable_id, :version], unique: true, name: "index_column_post_audits_on_auditable_and_version"
    add_index :column_post_audits, [:auditable_type, :auditable_id]
    add_index :column_post_audits, :request_uuid
    add_index :column_post_audits, :title
    add_index :column_post_audits, :published
  end
end
