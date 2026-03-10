ActiveAdmin.register Category do
  menu priority: 2

  includes :posts, :audits

  filter :id
  filter :name
  filter :created_at
  filter :updated_at

  index do
    selectable_column
    id_column
    column :name
    column :posts_count do |category|
      category.posts.size
    end
    column :audits_count do |category|
      category.audits.size if category.respond_to?(:audits)
    end
    column :created_at
    column :updated_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :created_at
      row :updated_at
    end

    panel "Posts" do
      table_for category.posts.includes(:author) do
        column :id
        column :title
        column :body do |post|
          body_text = post.body.to_s
          body_text.length > 100 ? "#{body_text[0, 100]}..." : body_text
        end
        column :author
        column :created_at
        column :actions do |post|
          link_to "View", admin_post_path(post), class: "button"
        end
      end
    end

    if category.respond_to?(:audits)
      panel "Recent Audits" do
        table_for category.audits.order(version: :desc).limit(10) do
          column :version
          column :action
          column :user
          column :comment
          column :created_at
        end
      end
    end

  end

  permit_params :name

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)

    f.inputs "Category Details" do
      f.input :name
    end

    f.actions
  end
end
