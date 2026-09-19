# frozen_string_literal: true

module Ledger
  module Appliers
    # CREATE_SECTION (Stage 20): one contribution creates one subtree of an
    # outline over a source. Payload: source_id (a root) or parent_section_id
    # (a subtree under an existing section), and sections: an ordered array
    # of {heading, location_id?, reading_location_id?, sections?}. Headings are
    # untrusted display text like notes. Accepted on validation, like
    # CREATE_CLAIM.
    #
    # Stage 30: a leaf may carry two locations over the same span.
    # location_id is the anchor, quoted exactly, which retrieval checks against
    # the source. reading_location_id is the section's text as an assistant read
    # it, cleaned into paragraphs, and must be typed TRANSCRIPTION: it is
    # readable, but it is not a quotation and nothing checks it against the
    # source. Keeping them apart is what stops edited speech being published
    # with a hash and a real name beside it.
    module CreateSection
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        parent = p["parent_section_id"].nil? ? nil : live!(Section, p, "parent_section_id")
        source = if parent
          reject("SCHEMA_INVALID", path("source_id"), "must equal the parent's source when given") if p["source_id"] && p["source_id"] != parent.source_id
          parent.source
        else
          live!(Source, p, "source_id")
        end
        nodes = p["sections"]
        reject("SCHEMA_INVALID", path("sections"), "expected a non-empty array of {heading, location_id?, sections?}") unless nodes.is_a?(Array) && nodes.any?
        count = check_nodes!(nodes, path("sections"), (parent&.depth || -1) + 1, source)
        reject("SCHEMA_INVALID", path("sections"), "at most #{Section::MAX_PER_CONTRIBUTION} sections in one contribution") if count > Section::MAX_PER_CONTRIBUTION
        if parent
          existing = Section.live.where(root_id: parent.root_id).count
          reject("SCHEMA_INVALID", path("sections"), "at most #{Section::MAX_PER_ROOT} sections under one root") if existing + count > Section::MAX_PER_ROOT
        end
      end

      def self.check_nodes!(nodes, at, depth, source)
        reject("SCHEMA_INVALID", at, "deeper than #{Section::MAX_DEPTH} levels") if depth >= Section::MAX_DEPTH
        nodes.each_with_index.sum do |node, i|
          here = "#{at}[#{i}]"
          reject("SCHEMA_INVALID", here, "expected an object") unless node.is_a?(Hash)
          heading = node["heading"]
          reject("SCHEMA_INVALID", "#{here}.heading", "expected a non-empty string of at most #{Section::MAX_HEADING} characters") unless heading.is_a?(String) && heading.strip.present? && heading.length <= Section::MAX_HEADING
          unless node["location_id"].nil?
            location = SourceLocation.find_by(id: node["location_id"].to_s)
            reject("TARGET_UNKNOWN", "#{here}.location_id", "no such location on this source") if location.nil? || location.source_id != source.id
          end
          unless node["reading_location_id"].nil?
            reading = SourceLocation.find_by(id: node["reading_location_id"].to_s)
            reject("TARGET_UNKNOWN", "#{here}.reading_location_id", "no such location on this source") if reading.nil? || reading.source_id != source.id
            unless reading.locator_type == "TRANSCRIPTION"
              reject("SCHEMA_INVALID", "#{here}.reading_location_id", "a reading must be a TRANSCRIPTION: cleaned text is not a quotation, and only a quotation is checked against the source")
            end
          end
          children = node.fetch("sections", [])
          reject("SCHEMA_INVALID", "#{here}.sections", "expected an array") unless children.is_a?(Array)
          1 + (children.any? ? check_nodes!(children, "#{here}.sections", depth + 1, source) : 0)
        end
      end

      def self.apply_payload(c, p, index = nil)
        parent = p["parent_section_id"] && Section.find(p["parent_section_id"])
        source_id = parent ? parent.source_id : p["source_id"]
        counter = 0
        start = parent ? Section.where(parent_id: parent.id).count : 0
        create_nodes(c, p["sections"], parent, source_id, start, index) { counter += 1; counter - 1 }
      end

      def self.create_nodes(c, nodes, parent, source_id, start, index, &next_index)
        nodes.each_with_index.map do |node, i|
          n = next_index.call
          id = row_id(c, "section", index ? "#{index}-#{n}" : n)
          section = Section.create!(
            id: id, contribution_id: c.id, created_seq: c.seq, source_id: source_id, root_id: parent ? parent.root_id : id,
            parent_id: parent&.id, depth: parent ? parent.depth + 1 : 0, position: start + i, heading: node["heading"].strip,
            location_id: node["location_id"], reading_location_id: node["reading_location_id"]
          )
          children = node.fetch("sections", [])
          create_nodes(c, children, section, source_id, 0, index, &next_index) if children.any?
          section
        end
      end
    end
  end
end
