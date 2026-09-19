# frozen_string_literal: true

module Sections
  # The readable text of a section (Stage 30).
  #
  # A leaf carries its own text. A branch has none of its own: its text is its
  # leaves' in document order, assembled here rather than stored, so nothing is
  # written twice and correcting one leaf corrects every level above it
  # (Invariant 2: a projection is derived, never a second copy).
  #
  # What comes back is a reading, not a quotation. The assistant that recorded
  # it cleaned it into paragraphs and corrected plain transcription errors, so
  # it is attributed and dated wherever it is shown, and never presented as the
  # speaker's exact words. The anchor beside it is the quotation.
  module Text
    NOTE = "A transcription, cleaned into paragraphs by the assistant named. Not a quotation: " \
           "the quoted anchor on each section is what is checked against the source."

    Part = Struct.new(:section, :text, :location, :depth, keyword_init: true)

    module_function

    # [Part] in document order, one per section that holds text.
    def call(section, seq)
      descendants(section, seq).filter_map do |node|
        reading = node.reading_location
        next if reading.nil? || reading.excerpt.blank?
        next unless reading.active_at?(seq)

        Part.new(section: node, text: reading.excerpt, location: reading, depth: node.depth - section.depth)
      end
    end

    def any?(section, seq) = call(section, seq).any?

    def characters(section, seq) = call(section, seq).sum { |part| part.text.length }

    # The section itself first, then everything beneath it, in the order the
    # outline puts them.
    def descendants(section, seq)
      all = Section.counted_at(seq).where(root_id: section.root_id).order(:depth, :position, :created_seq).to_a
      by_parent = all.group_by(&:parent_id)
      ordered = []
      walk = lambda do |node|
        ordered << node
        by_parent.fetch(node.id, []).sort_by { |c| [ c.position, c.created_seq ] }.each { |child| walk.call(child) }
      end
      walk.call(section)
      ordered
    end
  end
end
