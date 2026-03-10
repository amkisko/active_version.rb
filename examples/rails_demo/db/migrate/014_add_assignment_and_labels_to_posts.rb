class AddAssignmentAndLabelsToPosts < ActiveRecord::Migration[8.1]
  def change
    add_reference :posts, :assignee, foreign_key: { to_table: :users }
    add_column :posts, :labels_json, :json, null: false, default: []

    add_column :post_translations, :labels_json, :json, null: false, default: []

    add_column :post_revisions, :assignee_id, :integer
    add_column :post_revisions, :labels_json, :json, null: false, default: []
  end
end
