module TrackAttachmentReferences
  extend ActiveSupport::Concern

  included do
    before_destroy :capture_attachment_data_for_reference_tracking
    after_commit :sync_attachment_reference, on: %i[create update]
    after_commit :detach_attachment_reference, on: :destroy
  end

  private

  def sync_attachment_reference
    AttachmentReference.sync_for(
      self,
      attachment_name: :attachment,
      file_data: self[:attachment_data]
    )
  end

  def capture_attachment_data_for_reference_tracking
    @attachment_data_before_destroy = self[:attachment_data]
  end

  def detach_attachment_reference
    return if @attachment_data_before_destroy.blank?

    AttachmentReference.detach_for(self, attachment_name: :attachment)
  end
end
