class CreateColumnPosts < ActiveRecord::Migration[7.0]
  def change
    create_table :column_posts do |t|
      t.string :title, null: false
      t.text :body
      t.text :internal_notes
      t.boolean :published, null: false, default: false

      t.timestamps
    end
  end
end
