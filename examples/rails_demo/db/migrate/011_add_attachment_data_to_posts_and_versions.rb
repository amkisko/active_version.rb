class AddAttachmentDataToPostsAndVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :attachment_data, :text
    add_column :post_translations, :attachment_data, :text
    add_column :post_revisions, :attachment_data, :text
  end
end
