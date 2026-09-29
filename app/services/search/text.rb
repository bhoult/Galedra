# frozen_string_literal: true

module Search
  # Words found wherever the record keeps text a reader might remember: an
  # outline's section headings and the passages its sections quote and read, an
  # investigation's statement, a claim, and any other quoted passage (owner
  # request, 2026-09-29: "search in the interface to find text from an
  # investigation or outline"). The claims list searched claim text and nothing
  # else, so a phrase remembered from a section's reading had nowhere to go.
  #
  # The same rules as the pages that show these rows: counted at the head, not
  # taken down, and nothing from a quarantined claim or source (spec 05 §13).
  # Each group is capped, and the statement count does not grow with the number
  # of matches (spec/requests/search_spec.rb).
  #
  # websearch_to_tsquery reads a query the way people type one: "a quoted
  # phrase" must appear as a phrase, -word excludes, "or" alternates.
  module Text
    LIMIT = 20
    MAX_QUERY_CHARS = 300
    # Match markers that cannot occur in stored text, turned into <mark> only
    # after the text around them has been escaped: every snippet is somebody's
    # words, and none of them is markup (Invariant 11).
    OPEN = "\u0002"
    CLOSE = "\u0003"
    SNIPPET = "StartSel=#{OPEN}, StopSel=#{CLOSE}, MaxWords=30, MinWords=12, MaxFragments=2, FragmentDelimiter=\" … \"".freeze
    # Short text is shown whole: a fragment of a one-line statement drops its
    # first words and reads as a misquotation.
    WHOLE = 400
    WHOLE_TEXT = "HighlightAll=true, StartSel=#{OPEN}, StopSel=#{CLOSE}".freeze

    Result = Struct.new(:query, :sections, :investigations, :claims, :passages, keyword_init: true) do
      def empty? = [ sections, investigations, claims, passages ].all?(&:empty?)
      def total = [ sections, investigations, claims, passages ].sum(&:size)
    end

    module_function

    Q = "websearch_to_tsquery('english', ?)"

    def call(query, seq)
      q = query.to_s.squish
      return Result.new(query: q, sections: [], investigations: [], claims: [], passages: []) if q.empty?

      matching = passages_matching(q, seq)
      Result.new(query: q, sections: sections(q, seq, matching), investigations: investigations(q),
                 claims: claims(q, seq), passages: passages(q, seq, matching))
    end

    # Escaped, with the matched words in <mark>.
    def highlight(snippet)
      ERB::Util.html_escape(snippet.to_s).gsub(OPEN, "<mark>").gsub(CLOSE, "</mark>").html_safe # rubocop:disable Rails/OutputSafety
    end

    # A SQL fragment with the query bound, never interpolated.
    def bound(fragment, *values) = Arel.sql(ActiveRecord::Base.sanitize_sql_array([ fragment, *values ]))

    def headline(column, q, options) = bound("ts_headline('english', #{column}, #{Q}, ?)", q, options)

    def passages_matching(q, seq)
      SourceLocation.active_at(seq).where(redacted_by_seq: nil)
                    .where.not(source_id: Governance::Quarantines.quarantined_source_ids)
                    .where(source_id: Source.where(redacted_by_seq: nil).select(:id))
                    .where("to_tsvector('english', excerpt) @@ #{Q}", q)
    end

    # A section matches on its heading, or on the passage it is anchored to or
    # reads (Stage 30: a section's whole text is a passage like any other).
    def sections(q, seq, matching)
      ids = Section.counted_at(seq).where(redacted_by_seq: nil)
                   .where.not(source_id: Governance::Quarantines.quarantined_source_ids)
                   .where("to_tsvector('english', sections.heading) @@ #{Q} OR sections.location_id IN (?) OR sections.reading_location_id IN (?)",
                          q, matching.select(:id), matching.select(:id))
                   .order(bound("(to_tsvector('english', sections.heading) @@ #{Q}) DESC, sections.created_seq DESC", q))
                   .limit(LIMIT).pluck(:id)
      return [] if ids.empty?

      # Snippets for the rows that will be shown, never for every match.
      rows = Section.where(id: ids).joins("LEFT JOIN source_locations reading ON reading.id = sections.reading_location_id AND reading.redacted_by_seq IS NULL")
                    .joins("LEFT JOIN source_locations anchor ON anchor.id = sections.location_id AND anchor.redacted_by_seq IS NULL")
                    .pluck(:id, :root_id, :heading, headline("sections.heading", q, WHOLE_TEXT),
                           bound("CASE WHEN to_tsvector('english', coalesce(reading.excerpt, '')) @@ #{Q} THEN ts_headline('english', reading.excerpt, #{Q}, ?) " \
                                 "WHEN to_tsvector('english', coalesce(anchor.excerpt, '')) @@ #{Q} THEN ts_headline('english', anchor.excerpt, #{Q}, ?) END",
                                 q, q, SNIPPET, q, q, SNIPPET))
                    .index_by(&:first)
      roots = Section.where(id: rows.values.map { |r| r[1] }.uniq).pluck(:id, :heading).to_h
      ids.filter_map do |id|
        _, root_id, heading, heading_hl, text_hl = rows[id]
        next unless heading

        { id: id, heading: heading, heading_html: highlight(heading_hl), snippet_html: text_hl && highlight(text_hl),
          outline: root_id == id ? nil : roots[root_id], root_id: root_id }
      end
    end

    # Not one whose claims are all quarantined: its statement is usually the
    # withheld claim's own words. Stricter than the investigation page, which
    # still shows the statement; that page is a question for the owner.
    def investigations(q)
      Investigation.where.not(statement: [ nil, "" ]).where("to_tsvector('english', statement) @@ #{Q}", q)
                   .where.not("cardinality(claim_ids) > 0 AND claim_ids <@ ARRAY(?)", Governance::Quarantines.quarantined_claim_ids)
                   .order(created_at: :desc).limit(LIMIT)
                   .pluck(:id, :section_id, :created_at, :claim_ids,
                          bound("CASE WHEN length(statement) <= ? THEN ts_headline('english', statement, #{Q}, ?) ELSE ts_headline('english', statement, #{Q}, ?) END",
                                WHOLE, q, WHOLE_TEXT, q, SNIPPET))
                   .map { |id, section_id, at, claim_ids, hl| { id: id, section_id: section_id, created_at: at, claims: Array(claim_ids).size, snippet_html: highlight(hl) } }
    end

    def claims(q, seq)
      Claim.counted_at(seq).where(redacted_by_seq: nil).where.not(id: Governance::Quarantines.quarantined_claim_ids)
           .where("to_tsvector('english', canonical_text) @@ #{Q}", q)
           .order(created_seq: :desc).limit(LIMIT)
           .pluck(:id, :status, :claim_type, headline("canonical_text", q, WHOLE_TEXT))
           .map { |id, status, type, hl| { id: id, status: status, type: type, text_html: highlight(hl) } }
    end

    # Passages that are not a section's anchor or reading: those are listed
    # under their section, where they make sense.
    def passages(q, seq, matching)
      shown = Section.counted_at(seq).where("location_id IS NOT NULL OR reading_location_id IS NOT NULL")
      rows = matching.where.not(id: shown.select(:location_id).where.not(location_id: nil))
                     .where.not(id: shown.select(:reading_location_id).where.not(reading_location_id: nil))
                     .order(created_seq: :desc).limit(LIMIT)
                     .pluck(:id, :source_id, headline("excerpt", q, SNIPPET))
      return [] if rows.empty?

      sources = Source.where(id: rows.map { |r| r[1] }.uniq).pluck(:id, :title, :canonical_uri).to_h { |id, title, uri| [ id, [ title, uri ] ] }
      claim_for = EvidenceItem.where(source_location_id: rows.map(&:first)).joins("JOIN evidence_claim_links l ON l.evidence_item_id = evidence_items.id")
                              .where.not(l: { claim_id: Governance::Quarantines.quarantined_claim_ids })
                              .pluck(:source_location_id, Arel.sql("l.claim_id")).each_with_object({}) { |(loc, claim), h| h[loc] ||= claim }
      rows.map do |id, source_id, hl|
        title, uri = sources[source_id]
        { id: id, source_id: source_id, source_title: title, source_uri: uri, claim_id: claim_for[id], snippet_html: highlight(hl) }
      end
    end
  end
end
