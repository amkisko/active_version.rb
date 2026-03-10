#!/usr/bin/env ruby

require_relative "app"

DB[:work_item_translations].delete
DB[:work_item_audits].delete
DB[:work_item_revisions].delete
DB[:work_items].delete

puts "[runtime_adapter_example] adapter=#{ActiveVersion.runtime_adapter.class}"

item = nil
ActiveVersion.with_context(source: "runtime_adapter_example", actor: "demo") do
  item = SinatraDemo::WorkItem.create(
    kind: "post",
    title: "Runtime adapter post",
    body: "Initial content",
    labels: "demo,active_version",
    assignee: "demo.user"
  )
end

ActiveVersion.with_context(source: "runtime_adapter_example", actor: "demo", action: "update") do
  item.update(title: "Runtime adapter post v2", body: "Updated content")
end

ActiveVersion.with_context(source: "runtime_adapter_example", actor: "demo", action: "translate") do
  item.active_version_set_translation!(
    locale: "fi",
    title: "Ajoympäristön sovitin postaus",
    body: "Paivitetty sisältö",
    labels: "demo,suomi"
  )
end

puts "[runtime_adapter_example] item_id=#{item.id}"
puts "[runtime_adapter_example] revisions=#{item.active_version_revisions.count}"
puts "[runtime_adapter_example] audits=#{item.active_version_audits.count}"
puts "[runtime_adapter_example] translations=#{item.active_version_translations.count}"
puts "[runtime_adapter_example] fi.title=#{item.active_version_translate(:title, locale: :fi)}"
