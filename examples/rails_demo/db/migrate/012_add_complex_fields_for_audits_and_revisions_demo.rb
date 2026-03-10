class AddComplexFieldsForAuditsAndRevisionsDemo < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :settings_json, :json, null: false, default: {}
    add_column :posts, :flex_store, flex_store_column_type, null: false, default: {}
    add_column :posts, :status, :string, null: false, default: "draft"
    add_column :posts, :price, :decimal, precision: 12, scale: 4
    add_column :posts, :published_at, :datetime

    add_column :post_translations, :settings_json, :json, null: false, default: {}
    add_column :post_translations, :flex_store, flex_store_column_type, null: false, default: {}

    add_column :post_revisions, :settings_json, :json, null: false, default: {}
    add_column :post_revisions, :flex_store, flex_store_column_type, null: false, default: {}
    add_column :post_revisions, :status, :string, null: false, default: "draft"
    add_column :post_revisions, :price, :decimal, precision: 12, scale: 4
    add_column :post_revisions, :published_at, :datetime
  end

  private

  def flex_store_column_type
    postgres = connection.adapter_name.to_s.downcase.include?("postgres")
    return :json unless postgres

    extension_enabled?("hstore") ? :hstore : :json
  end
end
