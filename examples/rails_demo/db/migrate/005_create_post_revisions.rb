
class CreatePostRevisions < ActiveRecord::Migration[7.0]
  def change
    create_table :post_revisions do |t|
      t.references :post, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :title
      t.text :body

      t.timestamps
    end

    add_index :post_revisions, [:post_id, :version], unique: true
  end
end

