module Views
  module Posts
    class Index < BasePage
      def initialize(current_user:, notice:, alert:, posts:, total_translations:, total_revisions:, total_audits:)
        super(current_user:, notice:, alert:)
        @posts = posts
        @total_translations = total_translations
        @total_revisions = total_revisions
        @total_audits = total_audits
      end

      def view_template
        with_layout(title: "Posts · ActiveVersion Demo") do
          section(class: "card") do
            h1 { "Posts" }
            p(class: "muted") { "#{@posts.count} posts · #{@total_translations} translations · #{@total_revisions} revisions · #{@total_audits} audits" }
            div(class: "actions") { raw_html helpers.link_to("New Post", helpers.new_post_path, class: "btn primary") }
          end

          section(class: "card") do
            table do
              thead do
                tr do
                  th { "Title" }; th { "Status" }; th { "Category" }; th { "Author" }; th { "Assignee" }; th { "Created" }; th { "Actions" }
                end
              end
              tbody do
                @posts.each do |post|
                  tr do
                    td { raw_html helpers.link_to(post.title, helpers.post_path(post)) }
                    td { post.status.to_s }
                    td { post.category&.name.to_s }
                    td { post.author&.name.to_s }
                    td { post.assignee&.name.to_s }
                    td { post.created_at&.strftime("%Y-%m-%d %H:%M").to_s }
                    td do
                      raw_html helpers.link_to("Edit", helpers.edit_post_path(post))
                      plain " · "
                      raw_html helpers.link_to("Translations", helpers.translations_post_path(post))
                      plain " · "
                      raw_html helpers.link_to("Revisions", helpers.revisions_post_path(post))
                      plain " · "
                      raw_html helpers.link_to("Audits", helpers.audits_post_path(post))
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    class Show < BasePage
      def initialize(current_user:, notice:, alert:, post:, current_locale:)
        super(current_user:, notice:, alert:)
        @post = post
        @current_locale = current_locale
      end

      def view_template
        with_layout(title: "#{@post.title} · Post") do
          section(class: "card") do
            h1 { @post.title.to_s }
            p(class: "muted") { "Locale: #{@current_locale} · Status: #{@post.status}" }
            p { @post.body.to_s }
            div(class: "actions") do
              raw_html helpers.link_to("Edit", helpers.edit_post_path(@post), class: "btn primary")
              raw_html helpers.link_to("Translations", helpers.translations_post_path(@post), class: "btn")
              raw_html helpers.link_to("Revisions", helpers.revisions_post_path(@post), class: "btn")
              raw_html helpers.link_to("Audits", helpers.audits_post_path(@post), class: "btn")
              raw_html helpers.link_to("Diff", helpers.diff_post_path(@post), class: "btn")
            end
          end
        end
      end
    end

    class Form < BasePage
      def initialize(current_user:, notice:, alert:, post:, categories:, users:, action:)
        super(current_user:, notice:, alert:)
        @post = post
        @categories = categories
        @users = users
        @action = action
      end

      def view_template
        with_layout(title: (@post.new_record? ? "New Post" : "Edit Post")) do
          section(class: "card") do
            h1 { @post.new_record? ? "New Post" : "Edit Post" }
            raw_html post_form
          end
        end
      end

      private

      def post_form
        helpers.form_with(model: @post, url: @post.new_record? ? helpers.posts_path : helpers.post_path(@post), method: @post.new_record? ? :post : :patch, local: true, multipart: true) do |f|
          helpers.safe_join([
            field(f.label(:title) + f.text_field(:title, required: true)),
            field(f.label(:body) + f.text_area(:body, rows: 7)),
            field(f.label(:status) + f.select(:status, [["Draft", "draft"], ["Published", "published"], ["Archived", "archived"]])),
            field(f.label(:category_id, "Category") + f.collection_select(:category_id, @categories, :id, :name, include_blank: true)),
            field(f.label(:assignee_id, "Assignee") + f.collection_select(:assignee_id, @users, :id, :name, include_blank: true)),
            field(f.label(:labels_csv, "Labels") + f.text_field(:labels_csv)),
            field(f.label(:attachment) + f.file_field(:attachment)),
            field(f.label(:audit_comment, "Audit comment") + f.text_field(:audit_comment, name: "post[audit_comment]")),
            helpers.content_tag(:div, class: "actions") do
              helpers.safe_join([
                f.submit(@post.new_record? ? "Create Post" : "Update Post", class: "btn primary"),
                helpers.link_to("Cancel", @post.new_record? ? helpers.posts_path : helpers.post_path(@post), class: "btn")
              ])
            end
          ])
        end
      end

      def field(content)
        helpers.content_tag(:div, content, class: "field")
      end
    end

    class Translations < BasePage
      def initialize(current_user:, notice:, alert:, post:, current_locale:, available_locales:)
        super(current_user:, notice:, alert:)
        @post = post
        @current_locale = current_locale
        @available_locales = available_locales
      end

      def view_template
        current = @post.translations.find { |t| t.locale.to_s == @current_locale.to_s } || @post.translations.new(locale: @current_locale)

        with_layout(title: "Post Translations") do
          section(class: "card") do
            h1 { "Translations · #{@post.title}" }
            p(class: "muted") do
              @available_locales.map { |loc| helpers.link_to(loc.to_s.upcase, helpers.translations_post_path(@post, locale: loc)) }.join(" · ")
            end
            raw_html helpers.form_with(model: current, url: helpers.translations_post_path(@post), method: :patch, local: true, multipart: true) { |f|
              helpers.safe_join([
                helpers.hidden_field_tag("post_translation[locale]", @current_locale.to_s),
                field(f.label(:title) + f.text_field(:title)),
                field(f.label(:body) + f.text_area(:body, rows: 6)),
                field(f.label(:labels_csv) + f.text_field(:labels_csv)),
                field(f.label(:attachment) + f.file_field(:attachment)),
                helpers.content_tag(:div, class: "actions") { f.submit("Save Translation", class: "btn primary") }
              ])
            }
          end
        end
      end

      private

      def field(content)
        helpers.content_tag(:div, content, class: "field")
      end
    end

    class Revisions < BasePage
      def initialize(current_user:, notice:, alert:, post:, revisions:)
        super(current_user:, notice:, alert:)
        @post = post
        @revisions = revisions
      end

      def view_template
        with_layout(title: "Post Revisions") do
          section(class: "card") do
            h1 { "Revisions · #{@post.title}" }
            table do
              thead { tr { th { "Version" }; th { "Created" }; th { "Actions" } } }
              tbody do
                @revisions.each do |revision|
                  tr do
                    td { "v#{revision.version}" }
                    td { revision.created_at&.strftime("%Y-%m-%d %H:%M").to_s }
                    td do
                      raw_html helpers.button_to("Revert", helpers.revert_to_version_post_path(@post, version: revision.version), method: :post, class: "btn")
                      plain " "
                      raw_html helpers.button_to("Switch", helpers.switch_to_version_post_path(@post, version: revision.version), method: :post, class: "btn")
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    class Audits < BasePage
      def initialize(current_user:, notice:, alert:, post:, audits:)
        super(current_user:, notice:, alert:)
        @post = post
        @audits = audits
      end

      def view_template
        with_layout(title: "Post Audits") do
          section(class: "card") do
            h1 { "Audits · #{@post.title}" }
            table do
              thead { tr { th { "Version" }; th { "Action" }; th { "User" }; th { "When" } } }
              tbody do
                @audits.each do |audit|
                  tr do
                    td { "v#{audit.version}" }
                    td { audit.action.to_s }
                    td { audit.user&.name.to_s }
                    td { audit.created_at&.strftime("%Y-%m-%d %H:%M").to_s }
                  end
                end
              end
            end
          end
        end
      end
    end

    class Diff < BasePage
      def initialize(current_user:, notice:, alert:, post:, from_version:, to_version:, diff:)
        super(current_user:, notice:, alert:)
        @post = post
        @from_version = from_version
        @to_version = to_version
        @diff = diff
      end

      def view_template
        with_layout(title: "Post Diff") do
          section(class: "card") do
            h1 { "Diff · #{@post.title}" }
            p(class: "muted") { "From v#{@from_version} to v#{@to_version}" }
            pre { @diff.to_json }
          end
        end
      end
    end
  end
end
