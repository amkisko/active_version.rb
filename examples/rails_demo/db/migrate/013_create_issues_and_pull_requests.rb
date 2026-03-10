class CreateIssuesAndPullRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :issues do |t|
      t.string :title, null: false
      t.text :body
      t.string :status, null: false, default: "open"
      t.references :author, foreign_key: { to_table: :users }
      t.references :assignee, foreign_key: { to_table: :users }
      t.json :labels_json, null: false, default: []
      t.text :attachment_data

      t.timestamps
    end

    create_table :issue_translations do |t|
      t.references :issue, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :title
      t.text :body
      t.json :labels_json, null: false, default: []
      t.text :attachment_data

      t.timestamps
    end

    add_index :issue_translations, [:issue_id, :locale], unique: true
    add_index :issue_translations, :locale

    create_table :issue_revisions do |t|
      t.references :issue, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :title
      t.text :body
      t.string :status, null: false, default: "open"
      t.integer :author_id
      t.integer :assignee_id
      t.json :labels_json, null: false, default: []
      t.text :attachment_data

      t.timestamps
    end

    add_index :issue_revisions, [:issue_id, :version], unique: true

    create_table :pull_requests do |t|
      t.string :title, null: false
      t.text :body
      t.string :status, null: false, default: "open"
      t.string :source_branch, null: false, default: "feature"
      t.string :target_branch, null: false, default: "main"
      t.references :author, foreign_key: { to_table: :users }
      t.references :assignee, foreign_key: { to_table: :users }
      t.json :labels_json, null: false, default: []
      t.text :attachment_data

      t.timestamps
    end

    create_table :pull_request_translations do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :title
      t.text :body
      t.json :labels_json, null: false, default: []
      t.text :attachment_data

      t.timestamps
    end

    add_index :pull_request_translations, [:pull_request_id, :locale], unique: true, name: "index_pull_request_translations_on_pr_id_and_locale"
    add_index :pull_request_translations, :locale

    create_table :pull_request_revisions do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :title
      t.text :body
      t.string :status, null: false, default: "open"
      t.string :source_branch
      t.string :target_branch
      t.integer :author_id
      t.integer :assignee_id
      t.json :labels_json, null: false, default: []
      t.text :attachment_data

      t.timestamps
    end

    add_index :pull_request_revisions, [:pull_request_id, :version], unique: true, name: "index_pull_request_revisions_on_pr_id_and_version"
  end
end
