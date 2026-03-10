
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  PARAM_DELIMITER = ":"

  def self.param_to_id(param)
    return param if param.nil?

    if param.is_a?(String) && param.include?(PARAM_DELIMITER)
      param.split(PARAM_DELIMITER, 2)
    else
      param
    end
  end

  def self.id_to_param(id)
    id.is_a?(Array) ? id.join(PARAM_DELIMITER) : id
  end

  # Demo app default: allow ActiveAdmin/Ransack search on model columns and associations.
  # In production apps, prefer explicit per-model allowlists.
  def self.ransackable_attributes(_auth_object = nil)
    column_names
  end

  def self.ransackable_associations(_auth_object = nil)
    reflect_on_all_associations.map { |assoc| assoc.name.to_s }
  end
end
