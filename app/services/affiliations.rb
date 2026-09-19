# frozen_string_literal: true

# The affiliation vocabulary: the curated groups and options in
# config/affiliations.yml plus the entries admins add in response to
# requests (CustomAffiliation). Like Topics: closed, labelled, one reader.
module Affiliations
  PATH = Rails.root.join("config/affiliations.yml")
  Group = Struct.new(:slug, :label, :options, keyword_init: true)
  Option = Struct.new(:slug, :label, :group, :custom, keyword_init: true)

  module_function

  def curated_groups
    @curated_groups ||= YAML.safe_load(File.read(PATH)).fetch("groups").map do |g|
      group = Group.new(slug: g.fetch("slug"), label: g.fetch("label"), options: [])
      group.options.concat(g.fetch("options").map { |o| Option.new(slug: o.fetch("slug"), label: o.fetch("label"), group: group, custom: false) })
      group
    end
  end

  # Curated groups with the custom entries folded into their groups; an entry
  # whose group is unknown lands in "Other". Recomputed on each call: the
  # custom table is small and changes through the admin page.
  def groups
    groups = curated_groups.map { |g| Group.new(slug: g.slug, label: g.label, options: g.options.dup) }
    other = Group.new(slug: "other", label: "Other", options: [])
    CustomAffiliation.order(:label).each do |c|
      group = groups.find { |g| g.slug == c.group_slug } || other
      group.options << Option.new(slug: c.slug, label: c.label, group: group, custom: true)
    end
    other.options.any? ? groups + [ other ] : groups
  end

  def index = groups.flat_map(&:options).index_by(&:slug)
  def all = index.keys
  def valid?(slug) = index.key?(slug.to_s)
  def label(slug) = index[slug.to_s]&.label || slug.to_s
  def group_of(slug) = index[slug.to_s]&.group
  def group_slugs = curated_groups.map(&:slug) + [ "other" ]
end
