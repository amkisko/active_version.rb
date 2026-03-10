module Views
  module Issues
    class Index < BasePage
      def initialize(current_user:, notice:, alert:, issues:)
        super(current_user:, notice:, alert:)
        @issues = issues
      end

      def view_template
        with_layout(title: "Issues") do
          section(class: "card") do
            h1 { "Issues" }
            div(class: "actions") { raw_html helpers.link_to("New Issue", helpers.new_issue_path, class: "btn primary") }
          end
          section(class: "card") do
            table do
              thead { tr { th { "Title" }; th { "Status" }; th { "Author" }; th { "Assignee" }; th { "Actions" } } }
              tbody do
                @issues.each do |issue|
                  tr do
                    td { raw_html helpers.link_to(issue.title, helpers.issue_path(issue)) }
                    td { issue.status.to_s }
                    td { issue.author&.name.to_s }
                    td { issue.assignee&.name.to_s }
                    td do
                      raw_html helpers.link_to("Edit", helpers.edit_issue_path(issue))
                      plain " · "
                      raw_html helpers.link_to("Translations", helpers.translations_issue_path(issue))
                      plain " · "
                      raw_html helpers.link_to("Revisions", helpers.revisions_issue_path(issue))
                      plain " · "
                      raw_html helpers.link_to("Audits", helpers.audits_issue_path(issue))
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
      def initialize(current_user:, notice:, alert:, issue:, current_locale:)
        super(current_user:, notice:, alert:)
        @issue = issue
        @current_locale = current_locale
      end

      def view_template
        with_layout(title: @issue.title.to_s) do
          section(class: "card") do
            h1 { @issue.title.to_s }
            p(class: "muted") { "Locale: #{@current_locale} · Status: #{@issue.status}" }
            p { @issue.body.to_s }
            div(class: "actions") do
              raw_html helpers.link_to("Edit", helpers.edit_issue_path(@issue), class: "btn primary")
              raw_html helpers.link_to("Translations", helpers.translations_issue_path(@issue), class: "btn")
              raw_html helpers.link_to("Revisions", helpers.revisions_issue_path(@issue), class: "btn")
              raw_html helpers.link_to("Audits", helpers.audits_issue_path(@issue), class: "btn")
            end
          end
        end
      end
    end

    class Form < BasePage
      def initialize(current_user:, notice:, alert:, issue:, users:)
        super(current_user:, notice:, alert:)
        @issue = issue
        @users = users
      end

      def view_template
        with_layout(title: (@issue.new_record? ? "New Issue" : "Edit Issue")) do
          section(class: "card") do
            h1 { @issue.new_record? ? "New Issue" : "Edit Issue" }
            raw_html helpers.form_with(model: @issue, url: @issue.new_record? ? helpers.issues_path : helpers.issue_path(@issue), method: @issue.new_record? ? :post : :patch, local: true, multipart: true) { |f|
              helpers.safe_join([
                field(f.label(:title) + f.text_field(:title, required: true)),
                field(f.label(:body) + f.text_area(:body, rows: 7)),
                field(f.label(:status) + f.select(:status, [["Open", "open"], ["Closed", "closed"]])),
                field(f.label(:assignee_id, "Assignee") + f.collection_select(:assignee_id, @users, :id, :name, include_blank: true)),
                field(f.label(:labels_csv) + f.text_field(:labels_csv)),
                field(f.label(:attachment) + f.file_field(:attachment)),
                field(f.label(:audit_comment, "Audit comment") + f.text_field(:audit_comment, name: "issue[audit_comment]")),
                helpers.content_tag(:div, class: "actions") { f.submit(@issue.new_record? ? "Create Issue" : "Update Issue", class: "btn primary") }
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
      def initialize(current_user:, notice:, alert:, issue:, current_locale:, available_locales:)
        super(current_user:, notice:, alert:)
        @issue = issue
        @current_locale = current_locale
        @available_locales = available_locales
      end

      def view_template
        current = @issue.translations.find { |t| t.locale.to_s == @current_locale.to_s } || @issue.translations.new(locale: @current_locale)

        with_layout(title: "Issue Translations") do
          section(class: "card") do
            h1 { "Translations · #{@issue.title}" }
            p(class: "muted") { @available_locales.map { |loc| helpers.link_to(loc.to_s.upcase, helpers.translations_issue_path(@issue, locale: loc)) }.join(" · ") }
            raw_html helpers.form_with(model: current, url: helpers.translations_issue_path(@issue), method: :patch, local: true, multipart: true) { |f|
              helpers.safe_join([
                helpers.hidden_field_tag("issue_translation[locale]", @current_locale.to_s),
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
      def initialize(current_user:, notice:, alert:, issue:, revisions:)
        super(current_user:, notice:, alert:)
        @issue = issue
        @revisions = revisions
      end

      def view_template
        with_layout(title: "Issue Revisions") do
          section(class: "card") do
            h1 { "Revisions · #{@issue.title}" }
            table do
              thead { tr { th { "Version" }; th { "Created" }; th { "Actions" } } }
              tbody do
                @revisions.each do |revision|
                  tr do
                    td { "v#{revision.version}" }
                    td { revision.created_at&.strftime("%Y-%m-%d %H:%M").to_s }
                    td do
                      raw_html helpers.button_to("Revert", helpers.revert_to_version_issue_path(@issue, version: revision.version), method: :post, class: "btn")
                      plain " "
                      raw_html helpers.button_to("Switch", helpers.switch_to_version_issue_path(@issue, version: revision.version), method: :post, class: "btn")
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
      def initialize(current_user:, notice:, alert:, issue:, audits:)
        super(current_user:, notice:, alert:)
        @issue = issue
        @audits = audits
      end

      def view_template
        with_layout(title: "Issue Audits") do
          section(class: "card") do
            h1 { "Audits · #{@issue.title}" }
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
