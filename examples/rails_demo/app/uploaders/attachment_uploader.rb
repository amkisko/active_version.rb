class AttachmentUploader < Shrine
  Attacher.validate do
    validate_max_size 5 * 1024 * 1024, message: "is too large (max is 5 MB)"
  end
end
