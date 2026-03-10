class CreateAttachmentReferences < ActiveRecord::Migration[8.1]
  ATTACHMENT_TABLES = [
    :posts,
    :post_translations,
    :post_revisions,
    :issues,
    :issue_translations,
    :issue_revisions,
    :pull_requests,
    :pull_request_translations,
    :pull_request_revisions
  ].freeze

  def up
    create_table :attachment_references do |t|
      t.string :record_type, null: false
      t.string :record_pk, null: false
      t.string :attachment_name, null: false, default: "attachment"
      t.string :storage
      t.string :file_id
      t.json :file_data
      t.datetime :last_seen_at, null: false
      t.datetime :detached_at
      t.timestamps
    end

    add_index :attachment_references, [:record_type, :record_pk, :attachment_name], unique: true, name: "index_attachment_references_on_record_and_name"
    add_index :attachment_references, [:storage, :file_id], name: "index_attachment_references_on_storage_and_file_id"
    add_index :attachment_references, :detached_at

    backfill_existing_attachment_references
  end

  def down
    drop_table :attachment_references
  end

  private

  def backfill_existing_attachment_references
    conn = connection
    timestamp = Time.current

    ATTACHMENT_TABLES.each do |table|
      next unless column_exists?(table, :attachment_data)

      model_name = table.to_s.classify
      rows = conn.select_all("SELECT id, attachment_data FROM #{table} WHERE attachment_data IS NOT NULL AND attachment_data != ''")

      rows.each do |row|
        parsed = parse_json(row["attachment_data"])
        next if parsed.blank?

        conn.execute <<~SQL.squish
          INSERT INTO attachment_references
            (record_type, record_pk, attachment_name, storage, file_id, file_data, last_seen_at, detached_at, created_at, updated_at)
          VALUES
            (#{conn.quote(model_name)}, #{conn.quote(row["id"].to_s)}, 'attachment', #{conn.quote(parsed["storage"])}, #{conn.quote(parsed["id"])}, #{conn.quote(parsed.to_json)}, #{conn.quote(timestamp)}, NULL, #{conn.quote(timestamp)}, #{conn.quote(timestamp)})
          ON CONFLICT(record_type, record_pk, attachment_name)
          DO UPDATE SET
            storage = excluded.storage,
            file_id = excluded.file_id,
            file_data = excluded.file_data,
            last_seen_at = excluded.last_seen_at,
            detached_at = NULL,
            updated_at = excluded.updated_at
        SQL
      end
    end
  end

  def parse_json(value)
    JSON.parse(value)
  rescue JSON::ParserError
    nil
  end
end
