module Views
  module PullRequests
    class Index < BasePage
      def initialize(current_user:, notice:, alert:, pull_requests:)
        super(current_user:, notice:, alert:)
        @pull_requests = pull_requests
      end

      def view_template
        with_layout(title: "Pull Requests") do
          section(class: "card") do
            h1 { "Pull Requests" }
            div(class: "actions") { raw_html helpers.link_to("New Pull Request", helpers.new_pull_request_path, class: "btn primary") }
          end
          section(class: "card") do
            table do
              thead { tr { th { "Title" }; th { "Status" }; th { "Source" }; th { "Target" }; th { "Actions" } } }
              tbody do
                @pull_requests.each do |pr|
                  tr do
                    td { raw_html helpers.link_to(pr.title, helpers.pull_request_path(pr)) }
                    td { pr.status.to_s }
                    td { pr.source_branch.to_s }
                    td { pr.target_branch.to_s }
                    td do
                      raw_html helpers.link_to("Edit", helpers.edit_pull_request_path(pr))
                      plain " · "
                      raw_html helpers.link_to("Translations", helpers.translations_pull_request_path(pr))
                      plain " · "
                      raw_html helpers.link_to("Revisions", helpers.revisions_pull_request_path(pr))
                      plain " · "
                      raw_html helpers.link_to("Audits", helpers.audits_pull_request_path(pr))
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
      def initialize(current_user:, notice:, alert:, pull_request:, current_locale:)
        super(current_user:, notice:, alert:)
        @pull_request = pull_request
        @current_locale = current_locale
      end

      def view_template
        with_layout(title: @pull_request.title.to_s) do
          section(class: "card") do
            h1 { @pull_request.title.to_s }
            p(class: "muted") { "Locale: #{@current_locale} · #{@pull_request.source_branch} -> #{@pull_request.target_branch}" }
            p { @pull_request.body.to_s }
            div(class: "actions") do
              raw_html helpers.link_to("Edit", helpers.edit_pull_request_path(@pull_request), class: "btn primary")
              raw_html helpers.link_to("Translations", helpers.translations_pull_request_path(@pull_request), class: "btn")
              raw_html helpers.link_to("Revisions", helpers.revisions_pull_request_path(@pull_request), class: "btn")
              raw_html helpers.link_to("Audits", helpers.audits_pull_request_path(@pull_request), class: "btn")
            end
          end
        end
      end
    end

    class Form < BasePage
      def initialize(current_user:, notice:, alert:, pull_request:, users:)
        super(current_user:, notice:, alert:)
        @pull_request = pull_request
        @users = users
      end

      def view_template
        with_layout(title: (@pull_request.new_record? ? "New Pull Request" : "Edit Pull Request")) do
          section(class: "card") do
            h1 { @pull_request.new_record? ? "New Pull Request" : "Edit Pull Request" }
            raw_html helpers.form_with(model: @pull_request, url: @pull_request.new_record? ? helpers.pull_requests_path : helpers.pull_request_path(@pull_request), method: @pull_request.new_record? ? :post : :patch, local: true, multipart: true) { |f|
              helpers.safe_join([
                field(f.label(:title) + f.text_field(:title, required: true)),
                field(f.label(:body) + f.text_area(:body, rows: 7)),
                field(f.label(:status) + f.select(:status, [["Open", "open"], ["Merged", "merged"], ["Closed", "closed"]])),
                field(f.label(:source_branch) + f.text_field(:source_branch)),
                field(f.label(:target_branch) + f.text_field(:target_branch)),
                field(f.label(:assignee_id, "Assignee") + f.collection_select(:assignee_id, @users, :id, :name, include_blank: true)),
                field(f.label(:labels_csv) + f.text_field(:labels_csv)),
                field(f.label(:attachment) + f.file_field(:attachment)),
                field(f.label(:audit_comment, "Audit comment") + f.text_field(:audit_comment, name: "pull_request[audit_comment]")),
                helpers.content_tag(:div, class: "actions") { f.submit(@pull_request.new_record? ? "Create Pull Request" : "Update Pull Request", class: "btn primary") }
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

    class Translations < BasePage
      def initialize(current_user:, notice:, alert:, pull_request:, current_locale:, available_locales:)
        super(current_user:, notice:, alert:)
        @pull_request = pull_request
        @current_locale = current_locale
        @available_locales = available_locales
      end

      def view_template
        current = @pull_request.translations.find { |t| t.locale.to_s == @current_locale.to_s } || @pull_request.translations.new(locale: @current_locale)

        with_layout(title: "Pull Request Translations") do
          section(class: "card") do
            h1 { "Translations · #{@pull_request.title}" }
            p(class: "muted") { @available_locales.map { |loc| helpers.link_to(loc.to_s.upcase, helpers.translations_pull_request_path(@pull_request, locale: loc)) }.join(" · ") }
            raw_html helpers.form_with(model: current, url: helpers.translations_pull_request_path(@pull_request), method: :patch, local: true, multipart: true) { |f|
              helpers.safe_join([
                helpers.hidden_field_tag("pull_request_translation[locale]", @current_locale.to_s),
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
      def initialize(current_user:, notice:, alert:, pull_request:, revisions:)
        super(current_user:, notice:, alert:)
        @pull_request = pull_request
        @revisions = revisions
      end

      def view_template
        with_layout(title: "Pull Request Revisions") do
          section(class: "card") do
            h1 { "Revisions · #{@pull_request.title}" }
            table do
              thead { tr { th { "Version" }; th { "Created" }; th { "Actions" } } }
              tbody do
                @revisions.each do |revision|
                  tr do
                    td { "v#{revision.version}" }
                    td { revision.created_at&.strftime("%Y-%m-%d %H:%M").to_s }
                    td do
                      raw_html helpers.button_to("Revert", helpers.revert_to_version_pull_request_path(@pull_request, version: revision.version), method: :post, class: "btn")
                      plain " "
                      raw_html helpers.button_to("Switch", helpers.switch_to_version_pull_request_path(@pull_request, version: revision.version), method: :post, class: "btn")
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
      def initialize(current_user:, notice:, alert:, pull_request:, audits:)
        super(current_user:, notice:, alert:)
        @pull_request = pull_request
        @audits = audits
      end

      def view_template
        with_layout(title: "Pull Request Audits") do
          section(class: "card") do
            h1 { "Audits · #{@pull_request.title}" }
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
  end
end
