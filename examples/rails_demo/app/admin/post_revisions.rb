ActiveAdmin.register PostRevision, as: "PostRevision" do
  menu parent: "Posts", label: "Revisions"

  belongs_to :post, optional: true

  actions :index, :show

  includes :post

  filter :id
  filter :post_id
  filter :version
  filter :title
  filter :body
  filter :status
  filter :price
  filter :published_at
  filter :settings_json
  filter :flex_store
  filter :attachment_data
  filter :created_at

  scope :all, default: true
  scope :latest
  scope :oldest

  index do
    selectable_column
    id_column
    column("Post") do |revision|
      link_to revision.post.title, admin_post_path(revision.post) if revision.post
    end
    column("Version") { |revision| status_tag("v#{revision.version}", class: "ok") }
    column :title
    column :status
    column :price
    column("SEO Title") { |revision| revision.seo_title.presence || "—" }
    column("Body Preview") do |revision|
      body_text = revision.body.to_s
      body_text.length > 80 ? "#{body_text[0, 80]}..." : body_text
    end
    column("Attachment") do |revision|
      if revision.attachment.present?
        link_to(revision.attachment.original_filename || "Download", revision.attachment_url, target: "_blank", rel: "noopener")
      else
        "—"
      end
    end
    column("Created") { |revision| revision.created_at.strftime("%Y-%m-%d %H:%M") }
    actions
  end

  show do
    attributes_table do
      row :id
      row :post do
        link_to post_revision.post.title, admin_post_path(post_revision.post) if post_revision.post
      end
      row :version
      row :title
      row :body
      row :status
      row :price
      row :published_at
      row("SEO Title") { post_revision.seo_title.presence || "—" }
      row("Keywords CSV") { post_revision.keywords_csv.presence || "—" }
      row :settings_json
      row :flex_store
      row :attachment do
        if post_revision.attachment.present?
          link_to(post_revision.attachment.original_filename || "Download attachment", post_revision.attachment_url, target: "_blank", rel: "noopener")
        else
          "—"
        end
      end
      row :created_at
      row :updated_at
    end

    panel "View Post at This Version" do
      div do
        post_at_version = post_revision.post.revision(version: post_revision.version) if post_revision.post
        if post_at_version
          attributes_table_for post_at_version do
            row :title
            row :body
            row :category
            row :author
          end
          div do
            link_to "Revert to This Version", revert_to_version_admin_post_path(post_revision.post, version: post_revision.version), method: :post, class: "button", data: { confirm: "Are you sure you want to revert to version #{post_revision.version}? This will create a new revision." }
          end
          div do
            link_to "Switch to This Version", switch_to_version_admin_post_path(post_revision.post, version: post_revision.version), method: :post, class: "button", data: { confirm: "Are you sure you want to switch to version #{post_revision.version}?" }
          end
        else
          para "Could not load post at this version"
        end
      end
    end

    panel "Compare with Current Version" do
      div do
        current_post = post_revision.post
        revision_post = current_post.revision(version: post_revision.version) if current_post

        if revision_post
          table_for [
            { field: "Title", current: current_post.title, revision: revision_post.title },
            { field: "Body", current: current_post.body, revision: revision_post.body },
            { field: "Status", current: current_post.status, revision: revision_post.status },
            { field: "Price", current: current_post.price, revision: revision_post.price },
            { field: "SEO Title", current: current_post.seo_title, revision: revision_post.seo_title },
            { field: "Keywords CSV", current: current_post.keywords_csv, revision: revision_post.keywords_csv },
            { field: "Attachment", current: current_post.attachment&.original_filename, revision: revision_post.attachment&.original_filename }
          ] do
            column :field
            column :current_version
            column :revision_version
            column :different? do |row|
              row[:current] != row[:revision] ? status_tag("Yes", class: "yes") : status_tag("No", class: "no")
            end
          end
        else
          para "Could not compare versions"
        end
      end
    end
  end

  controller do
    def scoped_collection
      if params[:post_id]
        Post.find(params[:post_id]).revisions
      else
        super
      end
    end
  end
end
