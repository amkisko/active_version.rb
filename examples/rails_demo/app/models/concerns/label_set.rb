module LabelSet
  extend ActiveSupport::Concern

  def labels
    value = self[:labels_json]
    value.is_a?(Array) ? value : []
  end

  def labels_csv
    labels.join(", ")
  end

  def labels_csv=(value)
    parsed = value.to_s.split(",").map(&:strip).reject(&:blank?).uniq
    self.labels_json = parsed
  end
end
