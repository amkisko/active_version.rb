class CreateCompositeDemoAudits < ActiveRecord::Migration[8.0]
  def change
    create_table :composite_demo_audits, id: false, primary_key: [:audit_id, :partition_key] do |t|
      t.integer :audit_id, null: false
      t.date :partition_key, null: false

      t.string :auditable_type, null: false
      t.integer :auditable_id, null: false
      t.integer :version, null: false
      t.json :audited_changes, null: false, default: {}
      t.string :comment

      t.timestamps
    end

    add_index :composite_demo_audits, [:audit_id, :partition_key], unique: true, name: "index_composite_demo_audits_on_pk"
    add_index :composite_demo_audits,
              [:auditable_type, :auditable_id, :version, :partition_key],
              unique: true,
              name: "index_composite_demo_audits_on_logical_and_partition"
    add_index :composite_demo_audits, :partition_key
  end
end
