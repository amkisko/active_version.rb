module Views
  module SourceIdentityPosts
    class Index < BasePage
      def initialize(current_user:, notice:, alert:, source_identity_posts:)
        super(current_user:, notice:, alert:)
        @source_identity_posts = source_identity_posts
      end

      def view_template
        with_layout(title: "Source Partition Demo") do
          section(class: "card") do
            h1 { "Source + Version Partition Demo" }
            p(class: "muted") { "Source identity columns are copied into translation/revision/audit tables." }
          end
          section(class: "card") do
            table do
              thead { tr { th { "Title" }; th { "Tenant" }; th { "Source Key" }; th { "Partition" }; th { "Actions" } } }
              tbody do
                @source_identity_posts.each do |post|
                  tr do
                    td { raw_html helpers.link_to(post.title, helpers.source_identity_post_path(post)) }
                    td { post.tenant_id.to_s }
                    td { post.source_key.to_s }
                    td { post.partition_key.to_s }
                    td { raw_html helpers.link_to("View", helpers.source_identity_post_path(post)) }
                  end
                end
              end
            end
          end
        end
      end
    end

    class Show < BasePage
      def initialize(current_user:, notice:, alert:, source_identity_post:, translations:, revisions:, audits:)
        super(current_user:, notice:, alert:)
        @source_identity_post = source_identity_post
        @translations = translations
        @revisions = revisions
        @audits = audits
      end

      def view_template
        with_layout(title: @source_identity_post.title.to_s) do
          section(class: "card") do
            h1 { @source_identity_post.title.to_s }
            p(class: "muted") { "tenant_id=#{@source_identity_post.tenant_id} · source_key=#{@source_identity_post.source_key} · partition_key=#{@source_identity_post.partition_key}" }
          end

          div(class: "grid") do
            table_card("Translations", @translations, "locale")
            table_card("Revisions", @revisions, "version")
            table_card("Audits", @audits, "action")
          end
        end
      end

      private

      def table_card(title, records, first_key)
        section(class: "card") do
          h2 { title }
          table do
            thead { tr { th { first_key }; th { "Partition" }; th { "Created" } } }
            tbody do
              records.each do |record|
                tr do
                  td { record.public_send(first_key).to_s }
                  td { record.respond_to?(:partition_key) ? record.partition_key.to_s : "-" }
                  td { record.created_at&.strftime("%Y-%m-%d %H:%M").to_s }
                end
              end
            end
          end
        end
      end
    end
  end
end
