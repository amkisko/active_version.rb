ActiveAdmin.register PostAudit, as: "PostAudit" do
  menu parent: "Posts", label: "Audits"

  belongs_to :post, optional: true

  actions :index, :show

  includes :auditable, :user

  filter :id
  filter :auditable_id
  filter :auditable_type
  filter :action, as: :select, collection: ["create", "update", "destroy"]
  filter :version
  filter :user_id
  filter :user_type
  filter :comment
  filter :remote_address
  filter :request_uuid
  filter :created_at

  scope :all, default: true
  scope :creates
  scope :updates
  scope :destroys
  scope :with_comments
  scope :recent

  index do
    selectable_column
    id_column
    column("Post") do |audit|
      if audit.auditable&.respond_to?(:title)
        link_to audit.auditable.title, admin_post_path(audit.auditable)
      elsif audit.auditable
        link_to "Post ##{audit.auditable.id}", admin_post_path(audit.auditable)
      end
    end
    column("Action") do |audit|
      status_tag audit.action, class: audit.action
    end
    column("Version") { |audit| status_tag("v#{audit.version}", class: "ok") }
    column("Actor") { |audit| audit.user || "System" }
    column("Comment") do |audit|
      comment_text = audit.comment.to_s
      comment_text.length > 50 ? "#{comment_text[0, 50]}..." : comment_text
    end
    column("Changes") do |audit|
      changes = audit.audited_changes
      if changes.is_a?(Hash) && changes.any?
        "#{changes.keys.count} fields changed"
      else
        "No changes"
      end
    end
    column("IP", :remote_address)
    column("Request") do |audit|
      uuid = audit.request_uuid.to_s
      uuid.length > 8 ? uuid[0, 8] : uuid
    end
    column("Created") { |audit| audit.created_at.strftime("%Y-%m-%d %H:%M") }
    actions
  end

  show do
    attributes_table do
      row :id
      row :post do
        link_to post_audit.auditable.title, admin_post_path(post_audit.auditable) if post_audit.auditable
      end
      row :action do
        status_tag post_audit.action, class: post_audit.action
      end
      row :version
      row :user
      row :user_type
      row :comment
      row :remote_address
      row :request_uuid
      row :created_at
      row :updated_at
    end

    panel "Audited Changes" do
      changes = post_audit.audited_changes
      if changes.is_a?(Hash) && changes.any?
        table_for changes.to_a do
          column :field do |(key, value)|
            strong key
          end
          column :old_value do |(key, value)|
            if value.is_a?(Array)
              code value[0].to_s
            else
              code value.to_s
            end
          end
          column :new_value do |(key, value)|
            if value.is_a?(Array)
              code value[1].to_s
            else
              code value.to_s
            end
          end
        end
      else
        para "No changes recorded"
      end
    end

    panel "Audited Context" do
      context = post_audit.audited_context
      if context.is_a?(Hash) && context.any?
        pre JSON.pretty_generate(context)
      else
        para "No context recorded"
      end
    end

    panel "Reconstruct Post at This Version" do
      div do
        if post_audit.auditable && post_audit.auditable.respond_to?(:audit_revision)
          reconstructed = post_audit.auditable.audit_revision(version: post_audit.version)
          if reconstructed
            attributes_table_for reconstructed do
              row :title
              row :body
              row :category if reconstructed.respond_to?(:category)
              row :author if reconstructed.respond_to?(:author)
            end
          else
            para "Could not reconstruct post at this version"
          end
        else
          para "Post not available for reconstruction"
        end
      end
    end
  end

  controller do
    def scoped_collection
      if params[:post_id]
        Post.find(params[:post_id]).audits
      else
        super
      end
    end
  end
end
