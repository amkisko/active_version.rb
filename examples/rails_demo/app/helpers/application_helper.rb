
require "securerandom"

module ApplicationHelper
  def attachment_label(record)
    record.attachment&.original_filename.presence || "Download attachment"
  end

  def demo_prefill_token(namespace)
    @demo_prefill_tokens ||= {}
    @demo_prefill_tokens[namespace] ||= begin
      stamp = Time.current.strftime("%m%d%H%M%S")
      rand = SecureRandom.alphanumeric(4).downcase
      "#{namespace.upcase}-#{stamp}-#{rand}"
    end
  end
end
