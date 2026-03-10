module Views
  module ColumnPosts
    class Index < BasePage
      def initialize(current_user:, notice:, alert:, column_posts:, audit_counts_by_post_id:)
        super(current_user:, notice:, alert:)
        @column_posts = column_posts
        @audit_counts_by_post_id = audit_counts_by_post_id
      end

      def view_template
        with_layout(title: "Column Posts") do
          section(class: "card") do
            h1 { "Column-based Audit Demo" }
            p(class: "muted") { "Demonstrates table storage audits without audited_changes payload." }
          end
          section(class: "card") do
            table do
              thead { tr { th { "Title" }; th { "Published" }; th { "Audits" }; th { "Actions" } } }
              tbody do
                @column_posts.each do |post|
                  tr do
                    td { raw_html helpers.link_to(post.title, helpers.column_post_path(post)) }
                    td { post.published? ? "Yes" : "No" }
                    td { @audit_counts_by_post_id[post.id].to_i.to_s }
                    td { raw_html helpers.link_to("Edit", helpers.edit_column_post_path(post)) }
                  end
                end
              end
            end
          end
        end
      end
    end

    class Show < BasePage
      def initialize(current_user:, notice:, alert:, column_post:, audits:)
        super(current_user:, notice:, alert:)
        @column_post = column_post
        @audits = audits
      end

      def view_template
        with_layout(title: @column_post.title.to_s) do
          section(class: "card") do
            h1 { @column_post.title.to_s }
            p { @column_post.body.to_s }
            p(class: "muted") { "Published: #{@column_post.published? ? "Yes" : "No"}" }
            div(class: "actions") { raw_html helpers.link_to("Edit", helpers.edit_column_post_path(@column_post), class: "btn primary") }
          end
          section(class: "card") do
            h2 { "Audits" }
            table do
              thead { tr { th { "Version" }; th { "Action" }; th { "Title" }; th { "Published" }; th { "At" } } }
              tbody do
                @audits.each do |audit|
                  tr do
                    td { audit.version.to_s }
                    td { audit.action.to_s }
                    td { audit.title.to_s }
                    td { audit.published? ? "Yes" : "No" }
                    td { audit.created_at&.strftime("%Y-%m-%d %H:%M").to_s }
                  end
                end
              end
            end
          end
        end
      end
    end

    class Edit < BasePage
      def initialize(current_user:, notice:, alert:, column_post:)
        super(current_user:, notice:, alert:)
        @column_post = column_post
      end

      def view_template
        with_layout(title: "Edit Column Post") do
          section(class: "card") do
            h1 { "Edit Column Post" }
            raw_html helpers.form_with(model: @column_post, local: true) { |f|
              helpers.safe_join([
                helpers.content_tag(:div, f.label(:title) + f.text_field(:title, required: true), class: "field"),
                helpers.content_tag(:div, f.label(:body) + f.text_area(:body, rows: 7), class: "field"),
                helpers.content_tag(:div, f.label(:internal_notes) + f.text_area(:internal_notes, rows: 4), class: "field"),
                helpers.content_tag(:div, f.label(:published) + f.check_box(:published), class: "field"),
                helpers.content_tag(:div, f.label(:audit_comment, "Audit comment") + f.text_field(:audit_comment, name: "column_post[audit_comment]"), class: "field"),
                helpers.content_tag(:div, class: "actions") { f.submit("Update Column Post", class: "btn primary") }
              ])
            }
          end
        end
      end
    end
  end
end
