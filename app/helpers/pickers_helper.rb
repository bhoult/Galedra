# frozen_string_literal: true

# Choices a person makes from a list rather than by typing an id: a field that
# asks for a UUID is a field only somebody with a second tab open can fill in.
module PickersHelper
  # Every section in force, grouped under its outline and indented by depth, in
  # the outline's own order. One query: the tree is ordered here rather than by
  # asking each section for its children.
  def section_picker_options(seq, selected: nil)
    rows = Section.counted_at(seq).pluck(:id, :root_id, :parent_id, :position, :heading)
    by_parent = rows.group_by { |r| r[2] }
    ordered = ->(parent_id, depth) do
      (by_parent[parent_id] || []).sort_by { |r| r[3].to_i }.flat_map { |r| [ [ r, depth ] ] + ordered.call(r[0], depth + 1) }
    end
    groups = (by_parent[nil] || []).sort_by { |r| r[4].to_s.downcase }.map do |root|
      entries = [ [ root, 0 ] ] + ordered.call(root[0], 1)
      [ root[4].to_s.truncate(80), entries.map { |r, depth| [ "#{" " * depth}#{r[4].to_s.truncate(90)}", r[0] ] } ]
    end
    grouped_options_for_select(groups, selected)
  end

  # The topic vocabulary as boxes to tick, grouped under each top-level topic.
  def topic_picker_groups
    nodes = Topics.index.values
    nodes.select(&:top?).map { |top| [ top, nodes.select { |n| !n.top? && n.parent == top } ] }
  end
end
