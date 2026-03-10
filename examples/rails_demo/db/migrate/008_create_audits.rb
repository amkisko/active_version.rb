# Generic audits table for models using has_audits without a dedicated XxxAudit.
# Used when config.default_audit_class is set to Audit (single table for all audited models).
class CreateAudits < ActiveRecord::Migration[7.0]
  def change
    json_type = connection.adapter_name.downcase.include?("postgres") ? :jsonb : :json

    create_table :audits do |t|
      t.references :auditable, polymorphic: true, null: false
      t.references :user, polymorphic: true
      t.references :associated, polymorphic: true
      t.string :action, null: false
      t.public_send(json_type, :audited_changes, null: false, default: {})
      t.integer :version, null: false
      t.text :comment
      t.public_send(json_type, :audited_context, default: {})
      t.string :request_uuid
      t.string :remote_address

      t.timestamps
    end

    add_index :audits, [:auditable_type, :auditable_id, :version], unique: true, name: "index_audits_on_auditable_and_version"
    add_index :audits, [:auditable_type, :auditable_id]
    add_index :audits, [:user_type, :user_id]
    add_index :audits, :request_uuid
  end
end
