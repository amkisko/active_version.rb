require "json"
require "cgi"
require "rack/mock"
require "rack/utils"
require "securerandom"

class CommandLineExecutor
  FEATURE_ROUTES = {
    "translations" => "post_translations",
    "revisions" => "post_revisions",
    "audits" => "post_audits"
  }.freeze

  def initialize(current_user:)
    @current_user = current_user
    ActiveAdmin.application.load!
  end

  def execute(raw_command)
    command = normalize(raw_command)
    return failure("Empty command. Type `help` for examples.") if command.empty?

    return help if command == "help"
    return list_models if command == "models"

    execute_global_search(command) ||
      execute_search(command) ||
      execute_model_feature(command) ||
      execute_create(command) ||
      execute_update(command) ||
      execute_delete(command) ||
      execute_dot_syntax(command) ||
      execute_model_lookup(command) ||
      failure("Unknown command: #{command.inspect}. Type `help`.")
  rescue StandardError => error
    failure("#{error.class}: #{error.message}")
  end

  private

  def normalize(raw_command)
    raw_command.to_s.strip.sub(/\A:/, "").strip
  end

  def execute_dot_syntax(command)
    match = command.match(/\A([a-zA-Z_]+)\.(create|list|all|update|delete)\s*(?:\((.*)\))?\z/)
    return nil unless match

    resource = resolve_resource(match[1])
    return failure("Unknown model/resource: #{match[1]}") unless resource

    action = match[2]
    payload = match[3]

    return create_record(resource, payload) if action == "create"
    return list_records(resource) if %w[list all].include?(action)
    return update_record(resource, payload) if action == "update"
    return delete_record(resource, payload) if action == "delete"

    nil
  end

  def execute_create(command)
    direct = command.match(/\Acreate\s+([a-zA-Z_]+)(?:\s+(.*))?\z/)
    nested = command.match(/\A([a-zA-Z_]+)\s+create(?:\s+(.*))?\z/)
    match = direct || nested
    return nil unless match

    model_name = match[1]
    payload = match[2]
    resource = resolve_resource(model_name)
    return failure("Unknown model/resource: #{model_name}") unless resource

    create_record(resource, payload)
  end

  def execute_update(command)
    direct = command.match(/\Aupdate\s+([a-zA-Z_]+)\s+(\d+)(?:\s+(.*))?\z/)
    nested = command.match(/\A([a-zA-Z_]+)\s+update\s+(\d+)(?:\s+(.*))?\z/)
    match = direct || nested
    return nil unless match

    resource = resolve_resource(match[1])
    return failure("Unknown model/resource: #{match[1]}") unless resource

    payload = [match[2], match[3]].compact.join(" ").strip
    update_record(resource, payload)
  end

  def execute_delete(command)
    direct = command.match(/\Adelete\s+([a-zA-Z_]+)\s+(\d+)\z/)
    nested = command.match(/\A([a-zA-Z_]+)\s+delete\s+(\d+)\z/)
    match = direct || nested
    return nil unless match

    resource = resolve_resource(match[1])
    return failure("Unknown model/resource: #{match[1]}") unless resource

    delete_record(resource, match[2])
  end

  def execute_model_feature(command)
    match = command.match(/\Apost\s+(translations|revisions|audits)(?:\s+(\d+))?(?:\s+(.*))?\z/i)
    return nil unless match

    feature = match[1].downcase
    post_id = match[2]&.to_i
    options_tail = match[3]
    paging = extract_paging_options(options_tail)

    resource_route = FEATURE_ROUTES.fetch(feature)
    path = if post_id
      "/admin/posts/#{post_id}/#{resource_route}.json"
    else
      "/admin/#{resource_route}.json"
    end

    title = post_id ? "Post ##{post_id} #{feature}" : "All #{feature}"
    request_admin_json(:get, path, params: paging_query(paging), title: title, route_key: resource_route, paging: paging)
  end

  def execute_search(command)
    match = command.match(/\A([a-zA-Z_]+)\s+search\s+(.+)\z/)
    return nil unless match

    resource = resolve_resource(match[1])
    return failure("Unknown model/resource: #{match[1]}") unless resource

    paging = extract_paging_options(match[2])
    query = paging[:text]
    return failure("Search query can't be blank.") if query.empty?

    params = { q: { title_cont: query } }.merge(paging_query(paging))
    request_admin_json(
      :get,
      "/admin/#{resource[:route_key]}.json",
      params: params,
      title: "#{resource[:model_name]} search: #{query}",
      route_key: resource[:route_key],
      paging: paging
    )
  end

  def execute_global_search(command)
    match = command.match(/\Asearch\s+(.+)\z/)
    return nil unless match

    paging = extract_paging_options(match[1])
    query = paging[:text]
    return failure("Search query can't be blank.") if query.empty?

    targets = %w[posts issues pull_requests]
    lines = []

    targets.each do |route_key|
      params = { q: { title_cont: query } }.merge(paging_query(paging))
      parsed = parse_response(dispatch_request(:get, "/admin/#{route_key}.json", params))
      next unless parsed.is_a?(Array)
      next if parsed.empty?

      parsed.first(8).each do |record|
        next unless record.is_a?(Hash)

        id = record["id"]
        title = record["title"] || record["name"] || "untitled"
        status = record["status"]
        lines << {
          text: "[#{route_key}] ##{id} #{title}#{status ? " (#{status})" : ""}",
          href: public_show_path(route_key, id)
        }
      end
    end

    lines << paging_summary_line(paging) if lines.any?
    lines = ["No records found."] if lines.empty?
    success("Global search: #{query}", lines)
  end

  def execute_model_lookup(command)
    single_word = command.match(/\A([a-zA-Z_]+)\z/)
    model_with_id = command.match(/\A([a-zA-Z_]+)\s+(\d+)\z/)
    model_with_options = command.match(/\A([a-zA-Z_]+)\s+(.+)\z/)

    if model_with_id
      resource = resolve_resource(model_with_id[1])
      return failure("Unknown model/resource: #{model_with_id[1]}") unless resource

      return request_admin_json(
        :get,
        "/admin/#{resource[:route_key]}/#{model_with_id[2]}.json",
        title: "#{resource[:model_name]} ##{model_with_id[2]}",
        route_key: resource[:route_key]
      )
    end

    if single_word
      resource = resolve_resource(single_word[1])
      return nil unless resource

      return list_records(resource)
    end

    if model_with_options
      resource = resolve_resource(model_with_options[1])
      if resource
        paging = extract_paging_options(model_with_options[2])
        return list_records(resource, paging: paging) if paging[:found] && paging[:text].blank?
      end
    end

    nil
  end

  def resolve_resource(name)
    resource_map[normalize_model_name(name)]
  end

  def normalize_model_name(name)
    name.to_s.strip.tr("-", "_").underscore.downcase
  end

  def list_records(resource, paging: nil)
    paging ||= extract_paging_options(nil)
    request_admin_json(
      :get,
      "/admin/#{resource[:route_key]}.json",
      params: paging_query(paging),
      title: "#{resource[:model_name]} list",
      route_key: resource[:route_key],
      paging: paging
    )
  end

  def create_record(resource, payload)
    attributes = parse_attributes(payload)
    params = { resource[:param_key] => default_create_attributes(resource).merge(attributes) }

    request_admin_json(:post, "/admin/#{resource[:route_key]}.json", params: params, title: "#{resource[:model_name]} created", route_key: resource[:route_key])
  end

  def update_record(resource, payload)
    raw = payload.to_s.strip
    id = raw[/\A\d+/]
    return failure("Update requires id, e.g. `post update 1 title='New'`") unless id

    attrs = parse_attributes(raw.sub(/\A\d+\s*/, ""))
    params = { resource[:param_key] => attrs }
    request_admin_json(:put, "/admin/#{resource[:route_key]}/#{id}.json", params: params, title: "#{resource[:model_name]} updated", route_key: resource[:route_key])
  end

  def delete_record(resource, payload)
    id = payload.to_s.strip[/\d+/]
    return failure("Delete requires id, e.g. `delete post 1`") unless id

    request_admin_json(:delete, "/admin/#{resource[:route_key]}/#{id}.json", title: "#{resource[:model_name]} deleted")
  end

  def default_create_attributes(resource)
    case resource[:model_name]
    when "Post"
      { title: "CmdK Post #{Time.current.strftime('%H:%M:%S')}", body: "Created from command line.", status: "draft" }
    when "Category"
      { name: "CmdK Category #{Time.current.to_i}" }
    when "User"
      token = SecureRandom.hex(4)
      password = SecureRandom.hex(16)
      { name: "CmdK User #{token}", email: "cmdk_#{token}@example.com", password: password, password_confirmation: password }
    when "AdminUser"
      { email: "admin_#{SecureRandom.hex(4)}@example.com", encrypted_password: "" }
    when "Issue"
      { title: "CmdK Issue #{Time.current.strftime('%H:%M:%S')}", body: "Created from command line.", status: "open" }
    when "PullRequest"
      { title: "CmdK PR #{Time.current.strftime('%H:%M:%S')}", body: "Created from command line.", status: "open", source_branch: "feature/cmdk", target_branch: "main" }
    else
      {}
    end
  end

  def parse_attributes(payload)
    return {} if payload.blank?

    raw = payload.to_s.strip
    raw = raw[1..-2] if raw.start_with?("(") && raw.end_with?(")")
    pairs = raw.scan(/([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:=|:)\s*(\"[^\"]*\"|'[^']*'|[^,\s]+)/)

    attrs = {}
    pairs.each do |(key, value)|
      attrs[key] = cast_value(value)
    end
    attrs.transform_keys(&:to_sym)
  end

  def cast_value(value)
    normalized = value.to_s.strip
    normalized = normalized[1..-2] if (normalized.start_with?("\"") && normalized.end_with?("\"")) || (normalized.start_with?("'") && normalized.end_with?("'"))

    return nil if normalized == "nil"
    return true if normalized == "true"
    return false if normalized == "false"
    return normalized.to_i if normalized.match?(/\A-?\d+\z/)

    normalized
  end

  def request_admin_json(method, path, params: nil, title:, route_key: nil, paging: nil)
    response = dispatch_request(method, path, params)
    parsed = parse_response(response)

    if response.status.between?(200, 299)
      lines = format_response_lines(parsed, route_key: route_key)
      lines << paging_summary_line(paging) if paging && lines.any? && !lines.first.to_s.include?("No records found")
      success(title, lines)
    else
      lines = format_response_lines(parsed, route_key: route_key).map { |line| line_text(line) }
      lines.unshift("HTTP #{response.status}")
      failure(lines.join(" | "))
    end
  end

  def help
    success(
      "Command Help",
      [
        "post / issues / pull_requests / users (list)",
        "post 1",
        "create post title='Hello' body='World'",
        "post update 1 title='New title'",
        "delete post 1",
        "search release candidate",
        "search release candidate page 2 per 10",
        "posts search mobile spacing",
        "posts page 3 per 20",
        "issues search crash on save",
        "post.create(title:'Hello')",
        "post",
        "post translations",
        "post revisions",
        "post audits",
        "models"
      ]
    )
  end

  def list_models
    success("Supported ActiveAdmin resources", resource_map.values.map { |resource| resource[:route_key] }.uniq.sort)
  end

  def resource_map
    @resource_map ||= begin
      map = {}
      ActiveAdmin.application.namespaces.each do |namespace|
        namespace.resources.each do |resource|
          next unless resource.respond_to?(:resource_class)
          next unless resource.resource_class.table_exists?

          route_key = resource.resource_name.route_key
          singular = resource.resource_name.singular
          param_key = resource.resource_name.param_key
          model_name = resource.resource_class.name

          descriptor = { route_key: route_key, singular: singular, param_key: param_key, model_name: model_name }
          map[normalize_model_name(route_key)] = descriptor
          map[normalize_model_name(singular)] = descriptor
          map[normalize_model_name(model_name)] = descriptor
        end
      end
      map
    end
  end

  def dispatch_request(method, path, params)
    requested_path = path
    input = nil

    if method.to_s.downcase == "get" && params.present?
      query = Rack::Utils.build_nested_query(params)
      requested_path = "#{path}?#{query}"
    elsif params.present?
      input = Rack::Utils.build_nested_query(params)
    end

    headers = {
      "HTTP_HOST" => "localhost",
      "HTTP_ACCEPT" => "application/json"
    }
    headers["CONTENT_TYPE"] = "application/x-www-form-urlencoded" if input
    headers[:input] = input if input

    allow_forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    Rack::MockRequest.new(Rails.application).request(method.to_s.upcase, requested_path, headers)
  ensure
    ActionController::Base.allow_forgery_protection = allow_forgery
  end

  def parse_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError
    response.body.to_s
  end

  def format_response_lines(parsed, route_key: nil)
    case parsed
    when Array
      return ["No records found."] if parsed.empty?

      parsed.first(25).map { |record| format_hash_line(record, route_key: route_key) }
    when Hash
      [format_hash_line(parsed, route_key: route_key)]
    else
      [parsed.to_s.tr("\n", " ").truncate(500)]
    end
  end

  def format_hash_line(record, route_key: nil)
    return record.to_s unless record.is_a?(Hash)

    keys = %w[id title name email status locale action version created_at updated_at]
    fields = keys.filter_map { |key| "#{key}=#{record[key].inspect}" if record.key?(key) }
    fields = record.to_a.first(8).map { |(key, value)| "#{key}=#{value.inspect}" } if fields.empty?
    text = fields.join(" ")

    href = public_href_for_record(route_key, record)

    href ? { text: text, href: href } : text
  end

  def public_href_for_record(route_key, record)
    route = route_key.to_s
    id = record["id"]

    case route
    when "posts", "issues", "pull_requests", "categories", "users", "column_posts"
      public_show_path(route, id)
    when "post_translations"
      post_id = record["post_id"] || record["translatable_id"] || record["auditable_id"]
      post_id ? "/posts/#{post_id}/translations" : nil
    when "post_revisions"
      post_id = record["post_id"] || record["revisionable_id"] || record["auditable_id"]
      post_id ? "/posts/#{post_id}/revisions" : nil
    when "post_audits"
      post_id = record["post_id"] || record["auditable_id"]
      post_id ? "/posts/#{post_id}/audits" : nil
    when "issue_translations"
      issue_id = record["issue_id"] || record["translatable_id"] || record["auditable_id"]
      issue_id ? "/issues/#{issue_id}/translations" : nil
    when "issue_revisions"
      issue_id = record["issue_id"] || record["revisionable_id"] || record["auditable_id"]
      issue_id ? "/issues/#{issue_id}/revisions" : nil
    when "pull_request_translations"
      pull_request_id = record["pull_request_id"] || record["translatable_id"] || record["auditable_id"]
      pull_request_id ? "/pull_requests/#{pull_request_id}/translations" : nil
    when "pull_request_revisions"
      pull_request_id = record["pull_request_id"] || record["revisionable_id"] || record["auditable_id"]
      pull_request_id ? "/pull_requests/#{pull_request_id}/revisions" : nil
    when "audits"
      auditable_type = record["auditable_type"].to_s
      auditable_id = record["auditable_id"]
      case auditable_type
      when "Post"
        auditable_id ? "/posts/#{auditable_id}/audits" : nil
      when "Issue"
        auditable_id ? "/issues/#{auditable_id}/audits" : nil
      when "PullRequest"
        auditable_id ? "/pull_requests/#{auditable_id}/audits" : nil
      when "Category"
        auditable_id ? "/categories/#{auditable_id}" : nil
      else
        nil
      end
    else
      public_show_path(route, id) || (id ? "/admin/#{route}/#{id}" : nil)
    end
  end

  def public_show_path(route_key, id)
    return nil unless id.present?
    route = route_key.to_s
    return "/#{route}/#{id}" if %w[posts issues pull_requests categories users column_posts].include?(route)

    nil
  end

  def extract_paging_options(raw_tail)
    text = raw_tail.to_s.dup
    page_match = text.match(/(?:^|\s)(?:page|p)\s*=?\s*(\d+)\b/i)
    per_match = text.match(/(?:^|\s)(?:per|per_page)\s*=?\s*(\d+)\b/i)

    page = page_match ? page_match[1].to_i : 1
    per = per_match ? per_match[1].to_i : 25
    page = 1 if page < 1
    per = 25 if per < 1
    per = 100 if per > 100

    text.gsub!(/(?:^|\s)(?:page|p)\s*=?\s*\d+\b/i, " ")
    text.gsub!(/(?:^|\s)(?:per|per_page)\s*=?\s*\d+\b/i, " ")

    {
      text: text.strip,
      page: page,
      per_page: per,
      found: page_match.present? || per_match.present?
    }
  end

  def paging_query(paging)
    return {} unless paging

    {
      page: paging[:page],
      per_page: paging[:per_page]
    }
  end

  def paging_summary_line(paging)
    "Page #{paging[:page]} · #{paging[:per_page]} per page"
  end

  def line_text(line)
    return line[:text].to_s if line.is_a?(Hash)

    line.to_s
  end

  def normalize_text_lines(lines)
    Array(lines).map { |line| line_text(line) }
  end

  def success(title, lines)
    normalized_items = Array(lines).presence || ["No records found."]
    {
      ok: true,
      title: title,
      lines: normalize_text_lines(normalized_items),
      line_items: normalized_items
    }
  end

  def failure(message)
    { ok: false, title: "Command Error", lines: [message], line_items: [message] }
  end
end
