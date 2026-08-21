module ActiveVersion
  module UniqueVersionCollision
    module_function

    def match?(error, version_column: nil)
      return true if version_uniqueness_invalid?(error, version_column)

      unique_constraint_names_version?(error, version_column)
    end

    def version_uniqueness_invalid?(error, version_column)
      return false unless error.is_a?(ActiveRecord::RecordInvalid)
      return false if version_column.nil?

      details = error.record&.errors&.details
      return false unless details

      Array(details[version_column.to_sym]).any? { |detail| detail[:error] == :taken }
    end

    def unique_constraint_names_version?(error, version_column)
      needle = version_column.to_s
      return false if needle.empty?
      return false unless unique_constraint_error?(error)

      [error.message, error.cause&.message].compact.any? { |text| text.include?(needle) }
    end

    def unique_constraint_error?(error)
      return true if error.is_a?(ActiveRecord::RecordNotUnique)
      return false unless defined?(PG)

      error.is_a?(ActiveRecord::StatementInvalid) && error.cause.is_a?(PG::UniqueViolation)
    end

    private_class_method :version_uniqueness_invalid?, :unique_constraint_names_version?, :unique_constraint_error?
  end
end
