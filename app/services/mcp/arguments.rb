# frozen_string_literal: true

module Mcp
  # Stage 42 §1: a tool call is checked against the inputSchema it was handed,
  # before anything is built, signed or applied.
  #
  # Every refusal that cost a worker a round trip had one shape: it sent what the
  # published schema already forbade, and found out several layers down in a
  # vocabulary it had never been given — `$.payload.relevance_strength` for a
  # field it knew as `links[].strength`, or `CanonicalJson`'s "use an integer or
  # a decimal string" for a field whose values are five words, because signing
  # necessarily precedes applying. Checked here, a refusal names the field as the
  # schema names it and lists what it accepts, because the schema is the caller's
  # vocabulary. One source of truth, not a translation table.
  #
  # The subset is exactly what TOOLS uses — type, enum, properties, required,
  # items, minItems, maxItems, minimum, maximum — and nothing else, so no gem.
  #
  # **It must not refuse a call the server accepted before it existed.** Where a
  # declared type is stricter than what the tools have always read, this follows
  # the tools, not the schema:
  #
  # - an integer may arrive as a whole-number string or a whole float, because
  #   every integer argument is read with to_i and `links[].steps` accepts "2"
  #   on purpose (f6b9ae1);
  # - a plain string may arrive as a number, because every string argument is
  #   read with to_s — but a string with an enum may not, since no number is one
  #   of its words;
  # - a boolean may arrive as "true" or "false";
  # - null is absence, since clients send it for an optional field they left out;
  # - a key the schema does not name is left alone: aliases such as
  #   answer.searched are accepted by the tools and not declared.
  #
  # Values are never echoed: an argument may be untrusted text (Invariant 11).
  module Arguments
    module_function

    # Returns refusals in Ledger::Rejected's shape, each with `see`: the schema
    # fragment that was broken, so the caller can reread the contract without
    # another round trip (§6).
    def errors(schema, args)
      out = []
      check(schema, args, "$", "", out)
      out
    end

    def check(schema, value, path, name, out)
      return if schema.nil? || value.nil?

      schema = indifferent(schema)
      type = schema["type"]
      unless type.nil? || type_ok?(type, schema, value)
        return out << refusal(path, name, schema, "must be #{describe(type, schema)}; got #{kind_of(value)}")
      end

      if (words = schema["enum"]) && !words.map(&:to_s).include?(value.to_s)
        return out << refusal(path, name, schema, "must be one of #{words.join(', ')}")
      end

      case value
      when Hash then check_object(schema, value, path, out)
      when Array then check_array(schema, value, path, name, out)
      when Integer, Float, String then check_range(schema, value, path, name, out)
      end
    end

    def check_object(schema, value, path, out)
      properties = indifferent(schema["properties"] || {})
      Array(schema["required"]).map(&:to_s).each do |key|
        present = value.key?(key) && !value[key].nil? && !(value[key].is_a?(String) && value[key].strip.empty?)
        next if present

        state = value.key?(key) ? "is required and was sent empty" : "is required and was not sent"
        out << refusal(join(path, key), label(path, key), properties[key], state)
      end
      value.each do |key, v|
        sub = properties[key.to_s]
        check(sub, v, join(path, key), label(path, key), out) if sub
      end
    end

    def check_array(schema, value, path, name, out)
      if (min = schema["minItems"]) && value.size < min
        out << refusal(path, name, schema, "needs at least #{min} #{min == 1 ? 'item' : 'items'}; got #{value.size}")
      end
      if (max = schema["maxItems"]) && value.size > max
        out << refusal(path, name, schema, "takes at most #{max} #{max == 1 ? 'item' : 'items'}; got #{value.size}")
      end
      item = schema["items"]
      value.each_with_index { |v, i| check(item, v, "#{path}[#{i}]", "#{name}[#{i}]", out) } if item
    end

    def check_range(schema, value, path, name, out)
      return unless schema["type"] == "integer"

      number = value.is_a?(String) ? value.to_i : value
      out << refusal(path, name, schema, "must be at least #{schema['minimum']}") if schema["minimum"] && number < schema["minimum"]
      out << refusal(path, name, schema, "must be at most #{schema['maximum']}") if schema["maximum"] && number > schema["maximum"]
    end

    def type_ok?(type, schema, value)
      case type
      when "object" then value.is_a?(Hash)
      when "array" then value.is_a?(Array)
      when "boolean" then value == true || value == false || %w[true false].include?(value)
      when "integer" then value.is_a?(Integer) || (value.is_a?(Float) && value.finite? && value == value.floor) || (value.is_a?(String) && value.strip.match?(/\A-?\d+\z/))
      when "number" then value.is_a?(Numeric)
      when "string" then value.is_a?(String) || (schema["enum"].nil? && value.is_a?(Numeric))
      else true
      end
    end

    def describe(type, schema)
      return "one of #{schema['enum'].join(', ')}" if type == "string" && schema["enum"]

      { "object" => "an object", "array" => "a list", "boolean" => "true or false", "integer" => "a whole number",
        "number" => "a number", "string" => "text" }.fetch(type, type.to_s)
    end

    # What arrived, by kind — never its content.
    def kind_of(value)
      case value
      when Hash then "an object"
      when Array then "a list"
      when true, false then "true or false"
      when Integer then "a whole number"
      when Float then "a number with a fraction"
      when String then "text"
      else value.class.name.downcase
      end
    end

    def refusal(path, name, schema, what)
      field = name.presence || "the arguments"
      { code: "SCHEMA_INVALID", path: path, detail: "#{field} #{what}", see: see(schema) }.compact
    end

    # The broken part of the contract, trimmed to what a caller needs to fix it.
    def see(schema)
      return nil unless schema

      schema = indifferent(schema)
      fragment = schema.slice("type", "enum", "description", "minItems", "maxItems", "minimum", "maximum", "default")
      fragment["required"] = schema["required"] if schema["required"]
      fragment["properties"] = schema["properties"].keys.map(&:to_s) if schema["properties"]
      fragment.presence
    end

    def join(path, key) = "#{path}.#{key}"
    def label(path, key) = path == "$" ? key.to_s : "#{path.delete_prefix('$.')}.#{key}"

    def indifferent(hash) = hash.is_a?(Hash) ? hash.transform_keys(&:to_s) : hash
  end
end
