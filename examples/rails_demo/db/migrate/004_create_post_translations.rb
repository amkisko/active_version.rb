
class CreatePostTranslations < ActiveRecord::Migration[7.0]
  def change
    create_table :post_translations do |t|
      t.references :post, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :title
      t.text :body

      t.timestamps
    end

    add_index :post_translations, [:post_id, :locale], unique: true
    add_index :post_translations, :locale
  end
end

