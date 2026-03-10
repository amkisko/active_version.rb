require "shrine"
require "shrine/storage/file_system"

Shrine.storages = {
  cache: Shrine::Storage::FileSystem.new(Rails.root.join("tmp"), prefix: "uploads/cache"),
  store: Shrine::Storage::FileSystem.new(Rails.root.join("public"), prefix: "uploads/store")
}

Shrine.plugin :activerecord
Shrine.plugin :cached_attachment_data
Shrine.plugin :restore_cached_data
Shrine.plugin :determine_mime_type
Shrine.plugin :validation_helpers
Shrine.plugin :pretty_location
Shrine.plugin :keep_files
