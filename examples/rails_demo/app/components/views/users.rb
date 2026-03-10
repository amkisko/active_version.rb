module Views
  module Users
    class Show < BasePage
      def initialize(current_user:, notice:, alert:, user:, authored_posts:, authored_issues:, authored_pull_requests:, assigned_posts:, assigned_issues:, assigned_pull_requests:, user_audits:)
        super(current_user:, notice:, alert:)
        @user = user
        @authored_posts = authored_posts
        @authored_issues = authored_issues
        @authored_pull_requests = authored_pull_requests
        @assigned_posts = assigned_posts
        @assigned_issues = assigned_issues
        @assigned_pull_requests = assigned_pull_requests
        @user_audits = user_audits
      end

      def view_template
        with_layout(title: "#{@user.name} · Profile") do
          section(class: "card") do
            h1 { @user.name.to_s }
            p(class: "muted") { @user.email.to_s }
            div(class: "actions") { raw_html helpers.link_to("Edit Profile", helpers.edit_user_path(@user), class: "btn primary") }
          end

          div(class: "grid") do
            list_card("Authored Posts", @authored_posts)
            list_card("Authored Issues", @authored_issues)
            list_card("Authored Pull Requests", @authored_pull_requests)
            list_card("Assigned Posts", @assigned_posts)
            list_card("Assigned Issues", @assigned_issues)
            list_card("Assigned Pull Requests", @assigned_pull_requests)
          end

          section(class: "card") do
            h2 { "Recent Audits by User" }
            table do
              thead { tr { th { "Type" }; th { "Action" }; th { "Version" }; th { "At" } } }
              tbody do
                @user_audits.each do |audit|
                  tr do
                    td { audit.auditable_type.to_s }
                    td { audit.action.to_s }
                    td { audit.version.to_s }
                    td { audit.created_at&.strftime("%Y-%m-%d %H:%M").to_s }
                  end
                end
              end
            end
          end
        end
      end

      private

      def list_card(title, records)
        section(class: "card") do
          h2 { title }
          if records.any?
            ul do
              records.each { |record| li { raw_html helpers.link_to(record.title, helpers.polymorphic_path(record)) } }
            end
          else
            p(class: "muted") { "No records." }
          end
        end
      end
    end

    class Edit < BasePage
      def initialize(current_user:, notice:, alert:, user:)
        super(current_user:, notice:, alert:)
        @user = user
      end

      def view_template
        with_layout(title: "Edit Profile") do
          section(class: "card") do
            h1 { "Edit Profile" }
            raw_html helpers.form_with(model: @user, local: true) { |f|
              helpers.safe_join([
                helpers.content_tag(:div, f.label(:name) + f.text_field(:name, required: true), class: "field"),
                helpers.content_tag(:div, f.label(:email) + f.email_field(:email, required: true), class: "field"),
                helpers.content_tag(:div, f.label(:password) + f.password_field(:password), class: "field"),
                helpers.content_tag(:div, f.label(:password_confirmation) + f.password_field(:password_confirmation), class: "field"),
                helpers.content_tag(:div, class: "actions") { f.submit("Save Profile", class: "btn primary") }
              ])
            }
          end
        end
      end
    end
  end
end
