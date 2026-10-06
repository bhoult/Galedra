# frozen_string_literal: true

module Sources
  # Analyze text (Stage 46): a pasted text becomes a signed source and one
  # CLAIM_EXTRACTION task per reading window, and nothing else. The breakdown
  # into atomic claims is model work, and Galedra runs no model (Invariant 18):
  # it is done by an assistant, working a task or recording a check, or by a
  # person on the form, and each claim is a signed contribution of theirs.
  #
  # Until 2026-10-05 a sentence splitter proposed the claims here. It split on
  # punctuation, guessed types from keywords, shattered "Dr. Smith of the U.S.
  # Dept. of Energy" into five claims, and left every compound assertion whole
  # (implementation/implemented/stage-46-atomic-breakdown-by-the-assistant.md).
  module Paste
    # The same number the size rule gives assistants: past it, one check reads
    # only part of the text, so the text belongs in an outline.
    MAX_WORDS = Guidance::MAX_CHECK_WORDS

    class TooLong < StandardError
      attr_reader :words

      def initialize(words)
        @words = words
        super("#{words} words is over #{MAX_WORDS.to_fs(:delimited)}")
      end
    end

    module_function

    def call(user, text:, title: nil, source_type: "OTHER")
      words = text.split.size
      raise TooLong, words if words > MAX_WORDS

      payload = { "source_type" => source_type, "title" => title.presence || "Pasted text #{Time.now.utc.iso8601}",
                  "content" => text, "content_hash" => Crypto::Hashing.bytes(text) }
      result = Ui::Write.call(user, "CREATE_SOURCE", payload)
      source = Source.find(Ledger::Ids.derive(result.contribution.id, "source"))
      # The whole text, as before: what "Create verification tasks" points a
      # claim's evidence check at.
      whole = location(user, source, 0, source.content_length)
      ranges = windows(source.content)
      readers = ranges.size == 1 ? [ whole ] : ranges.map { |start, finish| location(user, source, start, finish) }
      creator = Ui::Write.contributor_for(user)
      readers.each { |loc| Tasks::Create.call(task_type: "CLAIM_EXTRACTION", target: source, location: loc, created_by: creator) }
      source
    end

    # The text's own principal broke it down, by hand or through its own
    # assistant's check, so the extraction tasks it opened no longer need a
    # volunteer. The same rule as an outline's leaves (Investigations::Record.
    # cancel_extraction_tasks). Cancelling a task is not a log event.
    def cancel_extraction!(source, principal_id)
      return 0 if principal_id.nil? || source.contribution&.principal_contributor_id != principal_id

      Task.where(task_type: "CLAIM_EXTRACTION", target_type: "SOURCE", target_id: source.id, section_id: nil, status: %w[OPEN LEASED])
          .update_all(status: "CANCELLED", cancelled_reason: Investigations::Record::RECORDED_BY_REQUESTER)
    end

    def location(user, source, start, finish)
      excerpt = source.slice(start, finish)
      result = Ui::Write.call(user, "CREATE_SOURCE_LOCATION",
                              { "source_id" => source.id, "locator_type" => "CHAR_RANGE", "locator" => { "start" => start, "end" => finish },
                                "excerpt" => excerpt, "excerpt_hash" => Crypto::Hashing.bytes(excerpt) })
      SourceLocation.find(Ledger::Ids.derive(result.contribution.id, "location"))
    end

    # Reading windows no longer than a packet carries (Tasks::Types::EXCERPT_CAP),
    # so an extraction task reads all of its window and none of the text goes
    # unread. A window ends at a paragraph break when there is one in its second
    # half, otherwise at the last space: this chooses where a reader's page
    # ends, never what a claim is. Each window is an exact slice, trimmed of
    # surrounding whitespace, so its excerpt hash verifies against the source.
    def windows(text, cap: Tasks::Types::EXCERPT_CAP)
      ranges = []
      start = 0
      while start < text.length
        start += 1 while start < text.length && text[start].match?(/\s/)
        break if start >= text.length

        finish = [ start + cap, text.length ].min
        if finish < text.length
          window = text[start...finish]
          cut = window.rindex(/\n\s*\n/)
          cut = window.rindex(/\s/) if cut.nil? || cut < cap / 2
          finish = start + cut if cut&.positive?
        end
        stop = finish
        stop -= 1 while stop > start && text[stop - 1].match?(/\s/)
        ranges << [ start, stop ]
        start = finish
      end
      ranges
    end
  end
end
