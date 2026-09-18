# frozen_string_literal: true

module Contributions
  # JSON Schema validation of the wire formats in schemas/ (spec 04 §11).
  module Schemas
    DIR = Rails.root.join("schemas")
    NAMES = %w[eir-contribution-v1 eir-task-v1 eir-result-v1].freeze

    module_function

    def schema(name)
      @schemas ||= {}
      @schemas[name] ||= JSONSchemer.schema(JSON.parse(File.read(DIR.join("#{name}.json"))), format: true)
    end

    # Returns [{code:, path:, detail:}] for every violation (empty when valid).
    def errors(name, document)
      schema(name).validate(document).map do |e|
        pointer = e["data_pointer"].to_s
        { code: "SCHEMA_INVALID", path: "$#{pointer.tr('/', '.')}", detail: "#{e['type']}: #{e['error'] || e['details']}".truncate(200) }
      end
    end

    def valid?(name, document) = errors(name, document).empty?
  end
end
