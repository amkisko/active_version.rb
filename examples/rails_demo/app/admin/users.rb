ActiveAdmin.register User do
  menu priority: 3

  includes :posts

  filter :id
  filter :name
  filter :email
  filter :created_at
  filter :updated_at

  index do
    selectable_column
    id_column
    column :name
    column :email
    column :posts_count do |user|
      user.posts.size
    end
    column :created_at
    column :updated_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :email
      row :created_at
      row :updated_at
    end

    panel "Posts" do
      table_for user.posts.includes(:category) do
        column :id
        column :title
        column :body do |post|
          body_text = post.body.to_s
          body_text.length > 100 ? "#{body_text[0, 100]}..." : body_text
        end
        column :category
        column :created_at
        column :actions do |post|
          link_to "View", admin_post_path(post), class: "button"
        end
      end
    end

  end

  permit_params :name, :email, :password, :password_confirmation

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)

    f.inputs "User Details" do
      f.input :name
      f.input :email
      f.input :password
      f.input :password_confirmation
    end

    f.actions
  end
end
