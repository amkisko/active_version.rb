#!/usr/bin/env ruby

require_relative "app"

DB[:work_item_translations].delete
DB[:work_item_audits].delete
DB[:work_item_revisions].delete
DB[:work_items].delete

item = SinatraDemo::WorkItem.create(
  kind: "issue",
  title: "Search ranking bug",
  body: "Exact matches should rank first.",
  labels: "bug,search",
  assignee: "qa.user"
)

item.update(
  title: "Search ranking bug (confirmed)",
  body: "Exact matches should rank first. Regression confirmed."
)

item.active_version_set_translation!(
  locale: "de",
  title: "Fehler in der Suchreihenfolge",
  body: "Exakte Treffer sollten zuerst erscheinen.",
  labels: "fehler,suche"
)

puts "[sequel_demo] kind=#{item.kind} id=#{item.id}"
puts "[sequel_demo] current_title=#{item.title}"
puts "[sequel_demo] translated_de_title=#{item.active_version_translate(:title, locale: :de)}"

puts "[sequel_demo] revisions:"
item.active_version_revisions.each do |revision|
  puts "  - v#{revision.version} title=#{revision.title.inspect} labels=#{revision.labels.inspect}"
end

puts "[sequel_demo] audits:"
item.active_version_audits.each do |audit|
  puts "  - v#{audit.version} action=#{audit.action.inspect} changes=#{audit.audited_changes}"
end

puts "[sequel_demo] translations:"
item.active_version_translations.each do |translation|
  puts "  - locale=#{translation.locale.inspect} title=#{translation.title.inspect}"
end
