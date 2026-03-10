module Views
  module Home
    class Index < BasePage
      def initialize(current_user:, notice:, alert:, posts:, issues:, pull_requests:)
        super(current_user:, notice:, alert:)
        @posts = posts
        @issues = issues
        @pull_requests = pull_requests
      end

      def view_template
        with_layout(title: "Home · ActiveVersion Demo") do
          div(class: "feed-layout") do
            div(class: "stack") do
              section(class: "card") do
                p(class: "kicker") { "Social Workspace" }
                h1 { "Social Demo Feed" }
                p(class: "muted") { "Track posts, issues, and pull requests in one stream while keeping audits, revisions, and translations attached." }
                div(class: "actions") do
                  raw_html helpers.link_to("New Post", helpers.new_post_path, class: "btn primary")
                  raw_html helpers.link_to("New Issue", helpers.new_issue_path, class: "btn")
                  raw_html helpers.link_to("New Pull Request", helpers.new_pull_request_path, class: "btn")
                end
              end

              section(class: "card") do
                p(class: "kicker") { "Latest Activity" }
                ul(class: "timeline") do
                  timeline_items.each do |item|
                    li(class: "timeline-item") do
                      div(class: "timeline-item-title") { raw_html helpers.link_to(item[:title], item[:path]) }
                      div(class: "timeline-item-meta") do
                        span { item[:kind] }
                        span { item[:status] } if item[:status].present?
                        span { item[:time] }
                      end
                      div(class: "timeline-item-actions") do
                        raw_html helpers.link_to("Open", item[:path])
                        raw_html helpers.link_to("Revisions", item[:revisions_path]) if item[:revisions_path]
                        raw_html helpers.link_to("Audits", item[:audits_path]) if item[:audits_path]
                      end
                    end
                  end
                end
              end
            end

            div(class: "stack") do
              section(class: "card") do
                p(class: "kicker") { "Overview" }
                h2 { "Workspace Snapshot" }
                div(class: "chip-list") do
                  span(class: "chip") { "Posts #{@posts.size}" }
                  span(class: "chip") { "Issues #{@issues.size}" }
                  span(class: "chip") { "Pull Requests #{@pull_requests.size}" }
                end
              end

              section(class: "card") do
                p(class: "kicker") { "Navigate" }
                div(class: "actions") do
                  raw_html helpers.link_to("Open Posts", helpers.posts_path, class: "btn")
                  raw_html helpers.link_to("Open Issues", helpers.issues_path, class: "btn")
                  raw_html helpers.link_to("Open Pull Requests", helpers.pull_requests_path, class: "btn")
                end
              end
            end
          end
        end
      end

      private

      def timeline_items
        items = []

        @posts.each do |record|
          items << {
            kind: "Post",
            title: record.title.to_s,
            status: record.status.to_s,
            time: record.created_at&.strftime("%Y-%m-%d %H:%M").to_s,
            path: helpers.post_path(record),
            revisions_path: helpers.revisions_post_path(record),
            audits_path: helpers.audits_post_path(record),
            created_at: record.created_at
          }
        end

        @issues.each do |record|
          items << {
            kind: "Issue",
            title: record.title.to_s,
            status: record.status.to_s,
            time: record.created_at&.strftime("%Y-%m-%d %H:%M").to_s,
            path: helpers.issue_path(record),
            revisions_path: helpers.revisions_issue_path(record),
            audits_path: helpers.audits_issue_path(record),
            created_at: record.created_at
          }
        end

        @pull_requests.each do |record|
          items << {
            kind: "Pull Request",
            title: record.title.to_s,
            status: record.status.to_s,
            time: record.created_at&.strftime("%Y-%m-%d %H:%M").to_s,
            path: helpers.pull_request_path(record),
            revisions_path: helpers.revisions_pull_request_path(record),
            audits_path: helpers.audits_pull_request_path(record),
            created_at: record.created_at
          }
        end

        items.sort_by { |item| item[:created_at] || Time.at(0) }.reverse.first(20)
      end
    end
  end
end
