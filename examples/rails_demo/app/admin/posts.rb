ActiveAdmin.register Post do
  menu priority: 1

  includes :category, :author, :translations, :revisions, :audits

  filter :id
  filter :title
  filter :body
  filter :status, as: :select, collection: %w[draft published archived]
  filter :price
  filter :published_at
  filter :settings_json
  filter :flex_store
  filter :attachment_data
  filter :category
  filter :author
  filter :created_at
  filter :updated_at

  scope :all, default: true
  scope :recent
  scope :with_translations
  scope :with_revisions

  index do
    selectable_column
    id_column
    column :title
    column :status
    column :price
    column("Attachment") { |post| post.attachment.present? ? status_tag("Yes", class: "ok") : status_tag("No") }
    column("Owner", &:author)
    column :category
    column("Feature Visibility") do |post|
      safe_join(
        [
          status_tag("#{post.translations.size} locales", class: "ok"),
          status_tag("#{post.revisions.size} revisions", class: "ok"),
          status_tag("#{post.audits.size} audits", class: "ok")
        ],
        " "
      )
    end
    column("Version") { |post| status_tag("v#{post.current_version}", class: "ok") }
    column("Updated") { |post| post.updated_at.strftime("%Y-%m-%d %H:%M") }
    actions
  end

  show do
    attributes_table do
      row :id
      row :title
      row :body
      row :status
      row :price
      row :published_at
      row("SEO Title") { |post| post.seo_title.presence || "—" }
      row("Keywords CSV") { |post| post.keywords_csv.presence || "—" }
      row("Calculated Score") { |post| post.calculated_score }
      row :settings_json
      row :flex_store
      row :attachment do |post|
        if post.attachment.present?
          link_to(post.attachment.original_filename || "Download attachment", post.attachment_url, target: "_blank", rel: "noopener")
        else
          "—"
        end
      end
      row :category
      row :author
      row :current_version
      row :created_at
      row :updated_at
    end

    panel "Translations" do
      table_for post.translations.order(:locale) do
        column :locale
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
      end
    end

    panel "Revisions" do
      table_for post.revisions.order(version: :desc).limit(10) do
        column :version
        column :title
        column :status
        column :price
        column("SEO Title") { |revision| revision.seo_title.presence || "—" }
        column :body do |revision|
          body_text = revision.body.to_s
          body_text.length > 100 ? "#{body_text[0, 100]}..." : body_text
        end
        column :attachment do |revision|
          if revision.attachment.present?
            link_to(revision.attachment.original_filename || "Download", revision.attachment_url, target: "_blank", rel: "noopener")
          else
            "—"
          end
        end
        column :created_at
        column :actions do |revision|
          link_to "View", admin_post_revision_path(post, revision), class: "button"
        end
      end
      div do
        link_to "View All Revisions", admin_post_revisions_path(post), class: "button"
      end
    end

    panel "Recent Audits" do
      table_for post.audits.order(version: :desc).limit(10) do
        column :version
        column :action
        column :user
        column :comment
        column :created_at
        column :actions do |audit|
          link_to "View", admin_post_audit_path(post, audit), class: "button"
        end
      end
      div do
        link_to "View All Audits", admin_post_audits_path(post), class: "button"
      end
    end

  end

  permit_params :title, :body, :attachment, :category_id, :author_id, :status, :price, :published_at, :seo_title, :keywords_csv,
    translations_attributes: [:id, :locale, :title, :body, :attachment, :seo_title, :keywords_csv, :_destroy],
    audit_comment: :string,
    audit_context: :hash

  form do |f|
    f.semantic_errors(*f.object.errors.attribute_names)

    f.inputs "Post Details" do
      f.input :title
      f.input :body, as: :text, input_html: { rows: 10 }
      f.input :status, as: :select, collection: %w[draft published archived], include_blank: false
      f.input :price
      f.input :published_at
      f.input :seo_title, input_html: { value: f.object.seo_title }, hint: "Virtual attr backed by settings_json[seo_title]"
      f.input :keywords_csv, input_html: { value: f.object.keywords_csv }, hint: "Virtual attr backed by flex_store[keywords]"
      f.input :attachment, as: :file, hint: (f.object.attachment.present? ? link_to(f.object.attachment.original_filename || "Current attachment", f.object.attachment_url, target: "_blank", rel: "noopener") : "No attachment")
      f.input :category
      f.input :author
    end

    f.inputs "Translations", "data-translations" => true do
      f.has_many :translations, heading: false, allow_destroy: true, new_record: true do |t|
        t.input :locale, as: :select, collection: I18n.available_locales.map { |l| [l.to_s, l.to_s] }, include_blank: false
        t.input :title
        t.input :body, as: :text, input_html: { rows: 5 }
        t.input :seo_title, input_html: { value: t.object.seo_title }, hint: "Virtual attr backed by settings_json[seo_title]"
        t.input :keywords_csv, input_html: { value: t.object.keywords_csv }, hint: "Virtual attr backed by flex_store[keywords]"
        t.input :attachment, as: :file, hint: (t.object.attachment.present? ? link_to(t.object.attachment.original_filename || "Current attachment", t.object.attachment_url, target: "_blank", rel: "noopener") : "No attachment")
      end
    end

    f.inputs "Audit Information" do
      f.input :audit_comment, as: :string, hint: "Optional comment for this change"
      f.input :audit_context, as: :text, hint: "JSON context (e.g., {\"ip\": \"127.0.0.1\", \"user_agent\": \"...\"})"
    end

    f.actions
  end

  member_action :revert_to_version, method: :post do
    version = params[:version].to_i
    if resource.revert_to(version: version)
      redirect_to resource_path, notice: "Reverted to version #{version}"
    else
      redirect_to resource_path, alert: "Failed to revert to version #{version}"
    end
  end

  member_action :switch_to_version, method: :post do
    version = params[:version].to_i
    if resource.switch_to!(version)
      redirect_to resource_path, notice: "Switched to version #{version}"
    else
      redirect_to resource_path, alert: "Failed to switch to version #{version}"
    end
  end

  action_item :revisions, only: :show do
    link_to "View All Revisions", admin_post_revisions_path(resource)
  end

  action_item :audits, only: :show do
    link_to "View All Audits", admin_post_audits_path(resource)
  end

  action_item :translations, only: :show do
    link_to "Manage Translations", admin_post_translations_path(resource)
  end
end
