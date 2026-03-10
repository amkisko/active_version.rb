require "bundler/setup"
require "sinatra/base"
require "sequel"
require "json"
require "active_version"

DB_PATH = File.expand_path("db/sinatra_demo.sqlite3", __dir__)
DB = Sequel.sqlite(DB_PATH)

unless DB.table_exists?(:work_items)
  DB.create_table :work_items do
    primary_key :id
    String :kind, null: false
    String :title, null: false
    Text :body
    String :labels
    String :assignee
    DateTime :created_at
    DateTime :updated_at
  end

  DB.add_index :work_items, :kind
  DB.add_index :work_items, :created_at
end

unless DB.table_exists?(:work_item_revisions)
  DB.create_table :work_item_revisions do
    primary_key :id
    foreign_key :work_item_id, :work_items, null: false, on_delete: :cascade
    Integer :version, null: false
    String :kind, null: false
    String :title, null: false
    Text :body
    String :labels
    String :assignee
    DateTime :created_at
    DateTime :updated_at
  end
  DB.add_index :work_item_revisions, [:work_item_id, :version], unique: true
end

unless DB.table_exists?(:work_item_audits)
  DB.create_table :work_item_audits do
    primary_key :id
    foreign_key :work_item_id, :work_items, null: false, on_delete: :cascade
    Integer :version, null: false
    String :action, null: false
    Text :audited_changes, null: false
    Text :audited_context, null: false, default: "{}"
    DateTime :created_at
    DateTime :updated_at
  end
  DB.add_index :work_item_audits, [:work_item_id, :version], unique: true
end

unless DB.table_exists?(:work_item_translations)
  DB.create_table :work_item_translations do
    primary_key :id
    foreign_key :work_item_id, :work_items, null: false, on_delete: :cascade
    String :locale, null: false
    String :title, null: false
    Text :body
    String :labels
    DateTime :created_at
    DateTime :updated_at
  end
  DB.add_index :work_item_translations, [:work_item_id, :locale], unique: true
end

module SinatraDemo
  class SequelRuntimeAdapter
    def initialize(db:)
      @db = db
    end

    def base_connection
      Connection.new(db: @db)
    end

    def connection_for(_model_class, _version_type)
      Connection.new(db: @db)
    end

    def supports_transactional_context?(_connection)
      false
    end

    def supports_current_transaction_id?(_connection)
      false
    end

    def supports_partition_catalog_checks?(_connection)
      false
    end

    class Connection
      def initialize(db:)
        @db = db
      end

      def adapter_name
        "SQLite"
      end

      def open_transactions
        0
      end

      def quote(value)
        "'#{value}'"
      end

      def execute(sql)
        @db.run(sql)
        []
      end
    end
  end
end

ActiveVersion.runtime_adapter = SinatraDemo::SequelRuntimeAdapter.new(db: DB)

require_relative "app/models/work_item"

module SinatraDemo
  class App < Sinatra::Base
    configure do
      set :method_override, true
      set :sessions, true
      set :protection, false
      set :views, File.expand_path("app/views", __dir__)
      set :public_folder, File.expand_path("app/public", __dir__)
    end

    helpers do
      def scope(kind)
        WorkItem.where(kind: kind).reverse_order(:created_at)
      end

      def nav_items
        [
          ["Home", "/"],
          ["Posts", "/posts"],
          ["Issues", "/issues"],
          ["Pull Requests", "/pull_requests"],
          ["Profile", "/profile"]
        ]
      end

      def kind_from_resource(resource)
        case resource
        when "posts" then "post"
        when "issues" then "issue"
        when "pull_requests" then "pull_request"
        else
          halt 404
        end
      end

      def resource_from_kind(kind)
        case kind
        when "post" then "posts"
        when "issue" then "issues"
        when "pull_request" then "pull_requests"
        else "posts"
        end
      end

      def default_title_for(kind)
        case kind
        when "post" then "A tiny post that ships value"
        when "issue" then "Improve search relevance on mobile"
        when "pull_request" then "Refactor feed card spacing"
        else "Untitled"
        end
      end

      def default_body_for(kind)
        case kind
        when "post" then "This post demonstrates a clean and short social update."
        when "issue" then "Observed behavior, expected behavior, and concise reproduction steps."
        when "pull_request" then "Summary of changes, screenshots, and validation notes."
        else ""
        end
      end

      def default_labels_for(kind)
        case kind
        when "post" then "announcement, demo"
        when "issue" then "bug, ui"
        when "pull_request" then "enhancement, reviewed"
        else ""
        end
      end
    end

    before do
      @active_path = request.path_info
    end

    get "/" do
      @posts = scope("post").limit(5).all
      @issues = scope("issue").limit(5).all
      @pull_requests = scope("pull_request").limit(5).all
      erb :index
    end

    get "/profile" do
      @all_items = WorkItem.reverse_order(:created_at).all
      erb :profile
    end

    get "/:resource" do
      kind = kind_from_resource(params[:resource])
      @resource = params[:resource]
      @kind = kind
      @items = scope(kind).all
      erb :list
    end

    get "/:resource/new" do
      kind = kind_from_resource(params[:resource])
      @resource = params[:resource]
      @kind = kind
      @item = WorkItem.new(
        kind: kind,
        title: default_title_for(kind),
        body: default_body_for(kind),
        labels: default_labels_for(kind),
        assignee: "demo.user"
      )
      erb :new
    end

    post "/:resource" do
      kind = kind_from_resource(params[:resource])
      payload = {
        kind: kind,
        title: params.fetch("title", "").strip,
        body: params.fetch("body", "").strip,
        labels: params.fetch("labels", "").strip,
        assignee: params.fetch("assignee", "").strip
      }

      ActiveVersion.with_context(route: request.path_info, action: "create") do
        item = WorkItem.new(payload)
        if item.valid?
          item.save
          redirect "/#{resource_from_kind(kind)}/#{item.id}"
        end

        @resource = params[:resource]
        @kind = kind
        @item = item
        status 422
        return erb(:new)
      end
    end

    get "/:resource/:id" do
      kind = kind_from_resource(params[:resource])
      @item = WorkItem.where(kind: kind, id: params[:id].to_i).first or halt 404
      @resource = params[:resource]
      @revisions = @item.active_version_revisions
      @audits = @item.active_version_audits
      @translations = @item.active_version_translations
      erb :show
    end

    get "/:resource/:id/edit" do
      kind = kind_from_resource(params[:resource])
      @item = WorkItem.where(kind: kind, id: params[:id].to_i).first or halt 404
      @resource = params[:resource]
      @kind = kind
      erb :edit
    end

    put "/:resource/:id" do
      kind = kind_from_resource(params[:resource])
      item = WorkItem.where(kind: kind, id: params[:id].to_i).first or halt 404

      ActiveVersion.with_context(route: request.path_info, action: "update") do
        item.set(
          title: params.fetch("title", "").strip,
          body: params.fetch("body", "").strip,
          labels: params.fetch("labels", "").strip,
          assignee: params.fetch("assignee", "").strip
        )

        if item.valid?
          item.save
          redirect "/#{params[:resource]}/#{item.id}"
        end

        @resource = params[:resource]
        @kind = kind
        @item = item
        status 422
        return erb(:edit)
      end
    end

    delete "/:resource/:id" do
      kind = kind_from_resource(params[:resource])
      item = WorkItem.where(kind: kind, id: params[:id].to_i).first or halt 404
      item.delete
      redirect "/#{params[:resource]}"
    end

    post "/:resource/:id/translations" do
      kind = kind_from_resource(params[:resource])
      item = WorkItem.where(kind: kind, id: params[:id].to_i).first or halt 404

      locale = params.fetch("locale", "").strip.downcase
      payload = {
        title: params.fetch("title", "").strip,
        body: params.fetch("body", "").strip,
        labels: params.fetch("labels", "").strip
      }

      ActiveVersion.with_context(route: request.path_info, action: "translate", locale: locale) do
        item.active_version_set_translation!(locale: locale, **payload.transform_keys(&:to_sym))
      end

      redirect "/#{params[:resource]}/#{item.id}"
    end
  end
end
