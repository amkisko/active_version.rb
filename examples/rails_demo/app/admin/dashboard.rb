ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    div class: "blank_slate_container", id: "dashboard_default_message" do
      span class: "blank_slate" do
        span "Welcome to ActiveVersion Demo"
        small "This demo showcases all ActiveVersion features: Translations, Revisions, and Audits"
      end
    end

    panel "Recent Posts" do
      ul do
        Post.order(created_at: :desc).limit(5).each do |post|
          li link_to(post.title, admin_post_path(post))
        end
      end
    end

    panel "Statistics" do
      ul do
        li "Total Posts: #{Post.count}"
        li "Total Translations: #{PostTranslation.count}"
        li "Total Revisions: #{PostRevision.count}"
        li "Total Audits: #{PostAudit.count}"
        li "Total Categories: #{Category.count}"
        li "Total Users: #{User.count}"
      end
    end

    panel "Recent Audits" do
      table_for PostAudit.includes(:auditable, :user).order(created_at: :desc).limit(10) do
        column :id
        column :post do |audit|
          if audit.auditable && audit.auditable.respond_to?(:title)
            link_to audit.auditable.title, admin_post_path(audit.auditable)
          elsif audit.auditable
            link_to "Post ##{audit.auditable.id}", admin_post_path(audit.auditable)
          end
        end
        column :action
        column :version
        column :user
        column :created_at
      end
    end

    panel "Recent Revisions" do
      table_for PostRevision.includes(:post).order(created_at: :desc).limit(10) do
        column :id
        column :post do |revision|
          link_to revision.post.title, admin_post_path(revision.post) if revision.post
        end
        column :version
        column :created_at
      end
    end

    panel "ActiveVersion Features" do
      div do
        h3 "Translations"
        p "Manage multi-locale content with automatic fallbacks and locale-specific editing."
        link_to "View Translations", admin_post_translations_path, class: "button"
      end
      div style: "margin-top: 20px;" do
        h3 "Revisions"
        p "Track version history, rollback to previous versions, and compare changes."
        link_to "View Revisions", admin_post_revisions_path, class: "button"
      end
      div style: "margin-top: 20px;" do
        h3 "Audits"
        p "Complete audit trail with user tracking, context, and change history."
        link_to "View Audits", admin_post_audits_path, class: "button"
      end
    end
  end
end
