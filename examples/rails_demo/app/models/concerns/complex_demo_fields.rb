module ComplexDemoFields
  extend ActiveSupport::Concern

  included do
    attr_accessor :runtime_note
  end

  def seo_title
    settings_hash["seo_title"].to_s
  end

  def seo_title=(value)
    self.settings_json = settings_hash.merge("seo_title" => value.to_s)
  end

  def keywords_csv
    flex_store_hash["keywords"].to_s.split("|").map(&:strip).reject(&:empty?).join(", ")
  end

  def keywords_csv=(value)
    normalized = value.to_s.split(/[,\|]/).map(&:strip).reject(&:empty?).uniq.join("|")
    self.flex_store = flex_store_hash.merge("keywords" => normalized)
  end

  def calculated_score
    (title.to_s.length + body.to_s.length) + keywords_count * 10
  end

  private

  def settings_hash
    value = self[:settings_json]
    value.is_a?(Hash) ? value : {}
  end

  def flex_store_hash
    value = self[:flex_store]
    value.is_a?(Hash) ? value : {}
  end

  def keywords_count
    raw = flex_store_hash["keywords"].to_s
    raw.split("|").map(&:strip).reject(&:empty?).size
  end
end
