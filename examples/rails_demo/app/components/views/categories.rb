module Views
  module Categories
    class Index < BasePage
      def initialize(current_user:, notice:, alert:, categories:, posts_count_by_category_id:, audits_count_by_category_id:)
        super(current_user:, notice:, alert:)
        @categories = categories
        @posts_count_by_category_id = posts_count_by_category_id
        @audits_count_by_category_id = audits_count_by_category_id
      end

      def view_template
        with_layout(title: "Categories") do
          section(class: "card") do
            h1 { "Categories" }
            div(class: "actions") { raw_html helpers.link_to("New Category", helpers.new_category_path, class: "btn primary") }
          end
          section(class: "card") do
            table do
              thead { tr { th { "Name" }; th { "Posts" }; th { "Audits" }; th { "Actions" } } }
              tbody do
                @categories.each do |category|
                  tr do
                    td { raw_html helpers.link_to(category.name, helpers.category_path(category)) }
                    td { @posts_count_by_category_id[category.id].to_i.to_s }
                    td { @audits_count_by_category_id[category.id].to_i.to_s }
                    td do
                      raw_html helpers.link_to("Edit", helpers.edit_category_path(category))
                      plain " · "
                      raw_html helpers.link_to("Delete", helpers.category_path(category), data: { turbo_method: :delete, turbo_confirm: "Delete category?" })
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
      def initialize(current_user:, notice:, alert:, category:, posts:)
        super(current_user:, notice:, alert:)
        @category = category
        @posts = posts
      end

      def view_template
        with_layout(title: @category.name.to_s) do
          section(class: "card") do
            h1 { @category.name.to_s }
            div(class: "actions") do
              raw_html helpers.link_to("Edit", helpers.edit_category_path(@category), class: "btn primary")
              raw_html helpers.link_to("Back", helpers.categories_path, class: "btn")
            end
          end
          section(class: "card") do
            h2 { "Posts in Category" }
            if @posts.any?
              ul do
                @posts.each { |post| li { raw_html helpers.link_to(post.title, helpers.post_path(post)) } }
              end
            else
              p(class: "muted") { "No posts in this category." }
            end
          end
        end
      end
    end

    class Form < BasePage
      def initialize(current_user:, notice:, alert:, category:)
        super(current_user:, notice:, alert:)
        @category = category
      end

      def view_template
        with_layout(title: (@category.new_record? ? "New Category" : "Edit Category")) do
          section(class: "card") do
            h1 { @category.new_record? ? "New Category" : "Edit Category" }
            raw_html helpers.form_with(model: @category, local: true) { |f|
              helpers.safe_join([
                helpers.content_tag(:div, f.label(:name) + f.text_field(:name, required: true), class: "field"),
                helpers.content_tag(:div, class: "actions") { f.submit(@category.new_record? ? "Create Category" : "Update Category", class: "btn primary") }
              ])
            }
          end
        end
      end
    end
  end
end
