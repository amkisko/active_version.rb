ActiveAdmin.register PostTranslation, as: "PostTranslation" do
  menu parent: "Posts", label: "Translations"

  belongs_to :post, optional: true

  actions :index, :show, :new, :create, :edit, :update, :destroy

  includes :post

  filter :id
  filter :post_id
  filter :locale, as: :select, collection: -> { I18n.available_locales.map { |l| [l.to_s, l.to_s] } }
  filter :title
  filter :body
  filter :settings_json
  filter :flex_store
  filter :attachment_data
  filter :created_at
  filter :updated_at

  scope :all, default: true

  index do
    selectable_column
    id_column
    column :post do |translation|
      link_to translation.post.title, admin_post_path(translation.post) if translation.post
    end
    column :locale do |translation|
      status_tag translation.locale, class: translation.locale
    end
    column :title
    column("SEO Title") { |translation| translation.seo_title.presence || "—" }
    column("Keywords CSV") { |translation| translation.keywords_csv.presence || "—" }
    column :body do |translation|
      body_text = translation.body.to_s
      body_text.length > 100 ? "#{body_text[0, 100]}..." : body_text
    end
    column :attachment do |translation|
      if translation.attachment.present?
        link_to(translation.attachment.original_filename || "Download", translation.attachment_url, target: "_blank", rel: "noopener")
      else
        "—"
      end
    end
    column :created_at
    column :updated_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :post do
        link_to post_translation.post.title, admin_post_path(post_translation.post) if post_translation.post
      end
      row :locale do
        status_tag post_translation.locale, class: post_translation.locale
      end
      row :title
      row :body
      row("SEO Title") { post_translation.seo_title.presence || "—" }
      row("Keywords CSV") { post_translation.keywords_csv.presence || "—" }
      row :settings_json
      row :flex_store
      row :attachment do
        if post_translation.attachment.present?
          link_to(post_translation.attachment.original_filename || "Download attachment", post_translation.attachment_url, target: "_blank", rel: "noopener")
        else
          "—"
        end
      end
      row :created_at
      row :updated_at
    end

    panel "Source Post" do
      div do
        attributes_table_for post_translation.post do
          row :title
          row :body
          row :category
          row :author
        end
      end
    end
  end

  permit_params :post_id, :locale, :title, :body, :attachment, :seo_title, :keywords_csv

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)

    f.inputs "Translation Details" do
      f.input :post, as: :select, collection: Post.all.map { |p| [p.title, p.id] }
      f.input :locale, as: :select, collection: I18n.available_locales.map { |l| [l.to_s, l.to_s] }, include_blank: false
      f.input :title
      f.input :body, as: :text, input_html: { rows: 10 }
      f.input :seo_title, input_html: { value: f.object.seo_title }, hint: "Virtual attr backed by settings_json[seo_title]"
      f.input :keywords_csv, input_html: { value: f.object.keywords_csv }, hint: "Virtual attr backed by flex_store[keywords]"
      f.input :attachment, as: :file, hint: (f.object.attachment.present? ? link_to(f.object.attachment.original_filename || "Current attachment", f.object.attachment_url, target: "_blank", rel: "noopener") : "No attachment")
    end

    f.actions
  end

  controller do
    def scoped_collection
      if params[:post_id]
        Post.find(params[:post_id]).translations
      else
        super
      end
    end
  end
end
