ActiveAdmin.register PullRequest do
  menu priority: 5

  includes :author, :assignee, :translations, :revisions, :audits

  filter :id
  filter :title
  filter :status, as: :select, collection: %w[open merged closed]
  filter :source_branch
  filter :target_branch
  filter :author
  filter :assignee
  filter :created_at
  filter :updated_at

  scope :all, default: true
  scope :recent

  index do
    selectable_column
    id_column
    column :title
    column :status
    column(:branches) { |pr| "#{pr.source_branch} -> #{pr.target_branch}" }
    column :author
    column :assignee
    column :updated_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :title
      row :body
      row :status
      row :source_branch
      row :target_branch
      row :labels_json
      row :author
      row :assignee
      row :created_at
      row :updated_at
    end
  end

  permit_params :title, :body, :status, :source_branch, :target_branch, :assignee_id, :labels_csv, :attachment,
    translations_attributes: [:id, :locale, :title, :body, :labels_csv, :attachment, :_destroy]

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)

    f.inputs "Pull Request" do
      f.input :title
      f.input :body, as: :text
      f.input :status, as: :select, collection: %w[open merged closed], include_blank: false
      f.input :source_branch
      f.input :target_branch
      f.input :labels_csv, input_html: { value: f.object.labels_csv }
      f.input :assignee
      f.input :attachment, as: :file
    end

    f.actions
  end
end
