# frozen_string_literal: true

module Sections
  # Indented headings (two spaces, or a tab, per level) to the nested payload
  # CREATE_SECTION takes. The first line at the shallowest level is the root
  # when there is exactly one; several top lines become siblings under a root
  # named after the first.
  module Outline
    module_function

    def parse(text)
      lines = text.to_s.lines.map(&:rstrip).reject(&:blank?)
      return [] if lines.empty?

      items = lines.map do |line|
        indent = line[/\A[ \t]*/].tr("\t", "  ").length / 2
        { depth: indent, node: { "heading" => line.strip[0, Section::MAX_HEADING], "sections" => [] } }
      end
      roots = []
      stack = []
      items.each do |item|
        stack.pop while stack.any? && stack.last[:depth] >= item[:depth]
        (stack.empty? ? roots : stack.last[:node]["sections"]) << item[:node]
        stack << item
      end
      strip(roots)
    end

    def strip(nodes)
      nodes.map { |n| n["sections"].empty? ? n.except("sections") : n.merge("sections" => strip(n["sections"])) }
    end
  end
end
