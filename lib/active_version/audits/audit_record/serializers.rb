require "json"
require "yaml"

module ActiveVersion
  module Audits
    module AuditRecord
      module Serializers
        class Identity
          def load(value) = value
          def dump(value) = value
        end

        class Json
          def load(value)
            return {} if value.nil?
            return value unless value.is_a?(String)

            JSON.parse(value)
          rescue JSON::ParserError => error
            ActiveVersion.log_debug(
              "[ActiveVersion::Audits::AuditRecord::Serializers::Json] failed to parse audit payload: #{error.message}"
            )
            value
          end

          def dump(value)
            return value unless value.is_a?(Hash) || value.is_a?(Array)

            JSON.generate(value)
          end
        end

        class Yaml
          PERMITTED_CLASSES = [Time, Date, DateTime, Symbol].freeze

          def load(value)
            return {} if value.nil?
            return value unless value.is_a?(String)

            YAML.safe_load(value, permitted_classes: PERMITTED_CLASSES, aliases: false)
          rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::AliasesNotEnabled, ArgumentError => error
            ActiveVersion.log_debug(
              "[ActiveVersion::Audits::AuditRecord::Serializers::Yaml] failed to parse audit payload: #{error.message}"
            )
            value
          end

          def dump(value)
            value.to_yaml
          end
        end
      end
    end
  end
end
