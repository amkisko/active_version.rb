class AttachmentReference < ApplicationRecord
  validates :record_type, :record_pk, :attachment_name, presence: true

  scope :active, -> { where(detached_at: nil) }
  scope :detached, -> { where.not(detached_at: nil) }

  def self.record_pk_for(record)
    ApplicationRecord.id_to_param(record.id).to_s
  end

  def self.sync_for(record, attachment_name: :attachment, file_data: nil)
    timestamp = Time.current
    reference = find_or_initialize_by(
      record_type: record.class.name,
      record_pk: record_pk_for(record),
      attachment_name: attachment_name.to_s
    )

    if file_data.blank?
      reference.storage = nil
      reference.file_id = nil
      reference.file_data = nil
      reference.last_seen_at ||= timestamp
      reference.detached_at = timestamp
      reference.save!
      return reference
    end

    parsed_data = file_data.is_a?(String) ? JSON.parse(file_data) : file_data

    reference.storage = parsed_data["storage"]
    reference.file_id = parsed_data["id"]
    reference.file_data = parsed_data
    reference.last_seen_at = timestamp
    reference.detached_at = nil
    reference.save!
    reference
  end

  def self.detach_for(record, attachment_name: :attachment)
    where(
      record_type: record.class.name,
      record_pk: record_pk_for(record),
      attachment_name: attachment_name.to_s
    ).update_all(detached_at: Time.current, updated_at: Time.current)
  end
end
