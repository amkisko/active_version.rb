
require "stringio"
require "securerandom"
require "bigdecimal"

demo_user_email = ENV.fetch("DEMO_USER_EMAIL", "demo@example.com")
reviewer_email = ENV.fetch("DEMO_REVIEWER_EMAIL", "reviewer@example.com")
admin_email = ENV.fetch("DEMO_ADMIN_EMAIL", "admin@example.com")

seed_password = ENV["DEMO_SEED_PASSWORD"]
generated_seed_password = false
if seed_password.to_s.strip.empty?
  seed_password = SecureRandom.base58(24)
  generated_seed_password = true
end

def build_text_upload(name, content)
  AttachmentUploader.upload(
    StringIO.new(content),
    :store,
    metadata: { "filename" => name, "mime_type" => "text/plain" }
  )
end

# Create demo user
user = User.find_or_create_by!(email: demo_user_email) do |u|
  u.name = "Demo User"
  u.password = seed_password
end

reviewer = User.find_or_create_by!(email: reviewer_email) do |u|
  u.name = "Reviewer User"
  u.password = seed_password
end

# Create categories
categories = [
  Category.find_or_create_by!(name: "Technology"),
  Category.find_or_create_by!(name: "Science"),
  Category.find_or_create_by!(name: "Arts")
]

# Create sample posts with translations
posts_data = [
  {
    title: "Welcome to ActiveVersion",
    body: "This is a demonstration of the ActiveVersion gem, showcasing translations, revisions, and audits.",
    category: categories[0],
    translations: {
      fi: {
        title: "Tervetuloa ActiveVersioniin",
        body: "Tämä on ActiveVersion-gemin esittely, joka esittelee käännökset, versiot ja tarkistukset."
      },
      sv: {
        title: "Välkommen till ActiveVersion",
        body: "Detta är en demonstration av ActiveVersion-gemmet, som visar översättningar, versioner och revisioner."
      }
    }
  },
  {
    title: "Understanding Versioning",
    body: "Versioning allows you to track changes, rollback to previous states, and maintain a complete audit trail.",
    category: categories[1],
    translations: {
      fi: {
        title: "Versionhallinnan ymmärtäminen",
        body: "Versionhallinta mahdollistaa muutosten seurannan, palauttamisen aiempiin tiloihin ja täydellisen tarkistuspolun ylläpidon."
      }
    }
  }
]

posts_data.each do |post_data|
  post = Post.create!(
    title: post_data[:title],
    body: post_data[:body],
    status: "draft",
    price: BigDecimal("19.9900"),
    published_at: Time.current,
    settings_json: { "source" => "seed", "seo_title" => "SEO #{post_data[:title]}" },
    flex_store: { "keywords" => "activeversion|demo|audit", "kind" => "seeded" },
    attachment: build_text_upload("post-#{SecureRandom.hex(4)}.txt", "Source attachment for '#{post_data[:title]}'"),
    category: post_data[:category],
    author: user,
    assignee: reviewer,
    labels_json: %w[announcement demo]
  )

  # Add translations
  post_data[:translations]&.each do |locale, translation_data|
    post.translations.create!(
      locale: locale.to_s,
      title: translation_data[:title],
      body: translation_data[:body],
      settings_json: { "seo_title" => "SEO #{translation_data[:title]}" },
      flex_store: { "keywords" => "#{locale}|translation|demo" },
      attachment: build_text_upload("translation-#{locale}-#{SecureRandom.hex(4)}.txt", "Translation attachment for #{locale}: #{translation_data[:title]}")
    )
  end

  # Create some revisions by updating the post
  2.times do |i|
    post.update!(
      title: "#{post.title} (Updated #{i + 1})",
      body: "#{post.body}\n\nThis is update #{i + 1}.",
      status: i.even? ? "published" : "archived",
      price: post.price.to_d + BigDecimal("1.5000"),
      settings_json: post.settings_json.merge("seo_title" => "SEO #{post.title} rev#{i + 1}"),
      flex_store: post.flex_store.merge("keywords" => "activeversion|revision#{i + 1}|demo"),
      labels_json: ["announcement", "rev#{i + 1}"],
      attachment: build_text_upload("post-revision-#{i + 1}-#{SecureRandom.hex(4)}.txt", "Revision #{i + 1} attachment for #{post.title}")
    )
  end
end

issue = Issue.find_or_create_by!(title: "Mobile spacing regression in feed") do |record|
  record.body = "Header spacing breaks on iPhone SE width. Need balanced spacing."
  record.status = "open"
  record.author = user
  record.assignee = reviewer
  record.labels_json = %w[bug mobile ui]
  record.attachment = build_text_upload("issue.txt", "Reproduction steps and screenshots list.")
end
issue.translations.find_or_create_by!(locale: "fi") do |tr|
  tr.title = "Mobiilin spacing-ongelma feedissä"
  tr.body = "Otsikon spacing rikkoutuu kapealla mobiilinäkymällä."
  tr.labels_json = %w[bug mobile]
end
issue.update!(status: "closed", labels_json: %w[bug mobile fixed])

pr = PullRequest.find_or_create_by!(title: "Polish responsive layout spacing") do |record|
  record.body = "Introduces balanced spacing scale and touch-friendly action rows."
  record.status = "open"
  record.source_branch = "feature/ios-spacing"
  record.target_branch = "main"
  record.author = reviewer
  record.assignee = user
  record.labels_json = %w[enhancement ux]
  record.attachment = build_text_upload("pr.diff.txt", "Pseudo diff for spacing updates.")
end
pr.translations.find_or_create_by!(locale: "sv") do |tr|
  tr.title = "Förfina responsiv spacing"
  tr.body = "Justerar mellanrum och positionering för mobila enheter."
  tr.labels_json = %w[ux mobile]
end
pr.update!(status: "merged", labels_json: %w[enhancement ux merged])

# Column-based audit storage demo
column_post = ColumnPost.find_or_create_by!(title: "Column Audit Example") do |cp|
  cp.body = "This record demonstrates audit rows with audited fields in dedicated columns."
  cp.internal_notes = "This should not be audited because only: [:title, :published] is configured."
  cp.published = false
end

column_post.audit_comment = "Publish state changed"
column_post.update!(published: true)

column_post.audit_comment = "Title updated"
column_post.update!(title: "Column Audit Example v2")

# Create admin user
AdminUser.find_or_create_by!(email: admin_email) do |admin|
  admin.encrypted_password = ENV.fetch("DEMO_ADMIN_ENCRYPTED_PASSWORD", SecureRandom.hex(64))
end

puts "Created #{User.count} users"
puts "Created #{Category.count} categories"
puts "Created #{AdminUser.count} admin users"
puts ""
puts "ActiveAdmin: direct access enabled (no login)"
puts "Created #{Post.count} posts"
puts "Created #{Issue.count} issues"
puts "Created #{PullRequest.count} pull requests"
puts "Created #{PostTranslation.count} translations"
puts "Created #{IssueTranslation.count} issue translations"
puts "Created #{PullRequestTranslation.count} pull request translations"
puts "Created #{PostRevision.count} revisions"
puts "Created #{IssueRevision.count} issue revisions"
puts "Created #{PullRequestRevision.count} pull request revisions"
puts "Created #{PostAudit.count} audits"
puts "Created #{ColumnPost.count} column audit demo records"
puts "Created #{ColumnPostAudit.count} column audit rows"
if generated_seed_password
  puts "Generated demo seed password for users: #{seed_password}"
  puts "Set DEMO_SEED_PASSWORD to make this deterministic."
end

# Composite primary key audit-like demo rows
today = Date.current
demo_rows = [
  {
    audit_id: 1,
    partition_key: today.beginning_of_month,
    auditable_type: "Post",
    auditable_id: 1,
    version: 1,
    audited_changes: {"title" => [nil, "Welcome to ActiveVersion"]},
    comment: "Initial create event"
  },
  {
    audit_id: 2,
    partition_key: today.beginning_of_month,
    auditable_type: "Post",
    auditable_id: 1,
    version: 2,
    audited_changes: {"title" => ["Welcome to ActiveVersion", "Welcome to ActiveVersion (Updated 1)"]},
    comment: "First update in same partition"
  },
  {
    audit_id: 1,
    partition_key: today.prev_month.beginning_of_month,
    auditable_type: "Post",
    auditable_id: 2,
    version: 1,
    audited_changes: {"status" => ["draft", "published"]},
    comment: "Different partition, same audit_id is valid"
  }
]

demo_rows.each do |attrs|
  CompositeDemoAudit.find_or_create_by!(
    audit_id: attrs[:audit_id],
    partition_key: attrs[:partition_key]
  ) do |row|
    row.auditable_type = attrs[:auditable_type]
    row.auditable_id = attrs[:auditable_id]
    row.version = attrs[:version]
    row.audited_changes = attrs[:audited_changes]
    row.comment = attrs[:comment]
  end
end

puts "Created #{CompositeDemoAudit.count} composite primary key demo rows"

# Mixed partitioning demo:
# - Source row keeps business composite identity (tenant_id/source_key/partition_key)
# - Destination tables carry the full identity columns to avoid parsing-based joins
source_demo = SourceIdentityPost.find_or_create_by!(
  tenant_id: "tenant-acme",
  source_key: "order-stream-42",
  partition_key: Date.current.beginning_of_month
) do |row|
  row.title = "Source partition identity demo"
  row.body = "Demonstrates source identity propagation into translations/revisions/audits."
  row.status = "draft"
end

source_demo.translations.find_or_create_by!(locale: "fi") do |tr|
  tr.tenant_id = source_demo.tenant_id
  tr.source_key = source_demo.source_key
  tr.partition_key = source_demo.partition_key
  tr.title = "Lähdepartition avaindemo"
  tr.body = "Käännösrivi sisältää koko lähdeavaimen."
  tr.status = "draft"
end

source_demo.audit_comment = "Promote to published for mixed partition demo"
source_demo.update!(status: "published", title: "#{source_demo.title} (Published)")

puts "Created #{SourceIdentityPost.count} source identity demo rows"
puts "Created #{SourceIdentityPostTranslation.count} source identity translations"
puts "Created #{SourceIdentityPostRevision.count} source identity revisions"
puts "Created #{SourceIdentityPostAudit.count} source identity audits"
