# frozen_string_literal: true

module Tasks
  # Stage 18: a task in plain form for a connected assistant, and its answer in
  # the investigation vocabulary (handles, not refs) translated into the
  # ordered TASK_RESULT ops. Every 04 §6 check still runs in the applier; this
  # only spares the assistant refs, packet hashes, and signing.
  module Answer
    HANDLE = /\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/
    RESERVED = %w[target packet].freeze
    SECTIONS = %w[sources excerpts claims edges evidence links groups supersede inferences].freeze

    ANSWER_WITH = {
      "EVIDENCE_VERIFICATION" =>
        "Read only the passage in context.untrusted_excerpt. Decide whether it directly bears on the claim. If it does, answer with evidence: [{handle, excerpt: \"packet\", statement}] and links: [{evidence, claim: \"target\", direction, strength, steps}]. Outcome CONFIRMED (the passage directly supports the claim), PARTIAL, NOT_SUPPORTED, or CANNOT_DETERMINE. Add no sources here.",
      "OPPOSING_EVIDENCE_SEARCH" =>
        "Search for evidence in context.search_direction; sources already counted are listed so you look elsewhere. Read what you find yourself. Answer FOUND with sources: [{handle, type, title, url, retrieved_at}], excerpts: [{handle, source, text, kind}], evidence: [{handle, excerpt, statement}], links: [{evidence, claim: \"target\", direction, strength, steps}]. Answer NONE_FOUND with an empty answer when a real search found nothing, and put what you covered in searched: the terms, where you looked, and why you concluded absence. That is a result, not a failure, and the coverage is what makes it one.",
      "SOURCE_INDEPENDENCE_CHECK" =>
        "Decide which of context.counted_evidence share one upstream origin (same press release, dataset, primary text, author). Answer GROUPED with groups: [{handle, type, description, members: [evidence_item_id, ...]}] using the ids from the packet; INDEPENDENT with an empty answer when none share an origin; CANNOT_DETERMINE when you cannot tell.",
      "QUALIFIER_CHECK" =>
        "Look in context.counted_links for omitted time ranges, populations, denominators, baselines, sampling limits, jurisdictions, or translations. Answer QUALIFIERS_FOUND with evidence and links of direction QUALIFY or CONTRADICT on claim: \"target\", or a narrower claim in claims: [{handle, text, type}] plus edges: [{from: handle, to: \"target\", type: \"NARROWS\"}], or supersede: [{link_id, direction, strength, steps, reason}] to revise a counted link. When the passage that shows the omission is not recorded yet, quote it here: sources: [{handle, type, title, url, retrieved_at}], excerpts: [{handle, source, text, kind}], with your evidence pointing at the excerpt's handle. NONE_MATERIAL with an empty answer when nothing material is missing; CANNOT_DETERMINE otherwise.",
      "INFERENCE_REVIEW" =>
        "Read context.premises and context.untrusted_rule. Answer VALID with an empty answer when the conclusion follows from the premises as stated; MISSING_PREMISE with claims: [{handle, text, type}] naming what the step silently assumes and inferences: [{handle, conclusion: \"target\", premises: [{claim, polarity}, ...], type, rule}] giving the corrected step (premises may be claim ids, handles, or \"target\"'s own premise claim ids); NON_SEQUITUR with a reason in the rule of a corrected inference or with an empty answer; CANNOT_DETERMINE otherwise. Do not judge whether the premises are true.",
      "CLAIM_EXTRACTION" =>
        "Split context.excerpts into atomic claims: claims: [{handle, text, type}], one assertion each, typed. Outcome CLAIMS_FOUND or NO_CLAIMS. Do not evaluate them."
    }.freeze

    RULES = "Read the sources yourself; Galedra never fetches URLs. Only quoted passages are evidence. A documented null result is a result. Never invent a source or pad an answer to have something to submit."

    module_function

    def present(task, assignment, base_url:)
      packet = task.packet
      spec = Types.spec(task.task_type)
      target_url = case task.target_type
      when "CLAIM" then "#{base_url}/claims/#{task.target_id}"
      when "INFERENCE" then "#{base_url}/claims/#{Inference.find(task.target_id).conclusion_claim_id}#inferences"
      else "#{base_url}/sources/#{task.target_id}"
      end
      context = packet["context"]
      if task.task_type == "EVIDENCE_VERIFICATION" && (location_id = context["source_location_id"])
        finding = SourceRetrieval.latest_for(context["source_id"])&.finding_for(location_id)
        context = context.merge("retrieval" => finding && {
          "found" => finding,
          "means" => SourceRetrieval.means(finding),
          "note" => "Galedra's own fetch of the page: #{SourceRetrieval.means(finding)}. A fact for you to weigh, not a verdict" \
                    "#{', and here it is not even that: open the document and read it yourself' if finding == 'NOT_READ'}."
        })
      end
      if task.section_id && (section = Section.find_by(id: task.section_id))
        context = context.merge("section" => { "id" => section.id, "path" => section.path, "url" => "#{base_url}/sections/#{section.id}",
                                               "note" => "Read this section of the source yourself, between the anchor and the next section's; the packet's excerpt is only the anchor." })
      end
      { task_id: task.id, task_type: task.task_type, domain: task.domain, objective: packet["objective"],
        target: packet["target"].merge("url" => target_url), context: context,
        outcomes: spec[:outcomes], constraints: constraints(packet, spec), moves: moves(task, assignment), lease_expires_at: assignment.lease_expires_at.utc.iso8601,
        task_url: "#{base_url}/tasks/#{task.id}", answer_with: ANSWER_WITH.fetch(task.task_type), rules: RULES }
    end

    # What answering can and cannot change, said before the work rather than
    # after it. An assistant worked two EVIDENCE_VERIFICATION tasks before
    # concluding the ceiling was "the quotation is faithful", then spent real web
    # searches on two claims that carry no probability at all, and asked for this
    # (docs/experiments/2026-09-20-second-connector-run.md).
    def moves(task, assignment = nil)
      # Checking your own principal's work is recorded as self-performed and
      # never raises review coverage (Stage 34). Saying a null search "raises how
      # well reviewed the claim is" was true in general and false for the lease
      # actually being handed over — reported by the assistant that read it and
      # then watched coverage stay at 0.00. This field exists to stop exactly
      # that, so it has to know whose work it is.
      own = assignment&.self_performed
      if task.target_type == "CLAIM" && unscoreable?(task.target_id)
        return "No model scores this claim's type, so it carries no probability and no outcome here moves its headline. " \
               "What it can still do is correct the type, which is a judgement and can be revised — say so if the claim is mistyped."
      end

      case task.task_type
      when "EVIDENCE_VERIFICATION"
        "Confirming this establishes that the quotation is faithful to its source. Where the passage comes from the same source the " \
        "claim was taken out of, that is provenance and not corroboration, so it will not move the headline on its own."
      when "OPPOSING_EVIDENCE_SEARCH"
        # The task type is named for the usual case, but the direction is
        # computed per claim: an unsupported claim is sent looking FOR evidence,
        # not against it (Tasks::BuildContext). This field said "against" either
        # way, so a worker handed a SUPPORT search was told the opposite of what
        # it had been asked for, in the one field whose job is to say what the
        # work can achieve before the effort is spent.
        wanted = task.packet.dig("context", "search_direction") == "SUPPORT" ? "for" : "against"
        "Finding evidence #{wanted} the claim moves the headline; this task asks you to search " \
        "#{wanted == 'for' ? 'FOR it, because nothing yet supports it' : 'AGAINST it'}. NONE_FOUND records a documented null search" +
          (own ? ", though it is your own principal's claim, so it is recorded as self-performed and does not raise review coverage: that needs a different principal." :
                 " and satisfies the opposing-search check, which raises how well reviewed the claim is.")
      when "QUALIFIER_CHECK"
        "A material qualifier recorded as QUALIFY or CONTRADICT moves the headline, and a narrower claim you record alongside it can be checked on its own." +
          (own ? " Review coverage will not move: this is your own principal's claim, so the check is recorded as self-performed." : "")
      else
        own ? "This is your own principal's claim, so answering is recorded as self-performed and does not raise review coverage." :
              "Answering satisfies one of this claim's review checks, which raises how well reviewed it is."
      end
    end

    def unscoreable?(claim_id)
      model = Scoring::Registry.default_model
      scored = model&.config&.fetch("scored_types", nil) or return false

      type = Claim.where(id: claim_id).pick(:claim_type)
      type.present? && !scored.include?(type)
    end

    # The caps the result is judged against, under the names the rejection uses
    # (TOO_MANY_OPS, OP_NOT_ALLOWED). They were in the stored packet and not in
    # what an assistant is handed, so the only way to learn them was to exceed one
    # (docs/experiments/2026-09-19-live-connector-outline.md, "not filed").
    def constraints(packet, spec)
      packet["constraints"] || { "allowed_ops" => spec[:allowed_ops], "max_ops" => spec[:max_ops] }
    end

    # Appends the TASK_RESULT for a leased task under the assistant's key.
    # A null search's coverage. Guidance told a worker to say what it searched
    # and the packet told it to answer with an empty answer; there was no field
    # that could hold the answer to the first, so both null searches in a run
    # left items: 0 and no record of the terms, the sources or the reasoning
    # (01a0c0d5). A positive finding carries its own source and is checkable; a
    # null is only as good as its coverage, and carried none.
    #
    # Clipped rather than refused, the way a report turn is: a caller told its
    # prose was too long by an exception has lost the prose.
    SEARCH_NOTE_MAX = 2_000

    # `submit_task`'s own arguments, which sit beside `answer` rather than inside
    # it. `searched` is the one a worker gets wrong, because coverage belongs to
    # the answer in every sense except the schema's. On 2026-09-22 Meta's Muse
    # put it there on its first attempt to supply a null's coverage — after 319
    # results with none — and was told only that the section was unknown, which
    # names the mistake and not the fix. A refusal that blocks the behaviour you
    # are trying to encourage is worse than no refusal at all.
    MISPLACED = %w[searched task_id outcome].freeze

    # Outcomes that say a search came up empty. A positive finding carries its
    # own source and anyone can check it; a null is worth exactly what its
    # coverage is worth, and coverage described only in chat is gone the moment
    # the conversation ends.
    ABSENCES = %w[NONE_FOUND NONE_MATERIAL CANNOT_DETERMINE NO_CLAIMS INDEPENDENT].freeze

    def submit(token, task, outcome:, answer:, searched: nil)
      answer, inside = lift_searched(answer)
      ops = ops_for(task, answer)
      note = (searched.presence || inside).to_s.strip.presence
      result = Assistants::Write.result(token, task, outcome: outcome.to_s, ops: ops, searched: note&.slice(0, SEARCH_NOTE_MAX))
      [ result, note.to_s.length > SEARCH_NOTE_MAX ]
    end

    # Coverage belongs to the answer in every sense except the schema's, where it
    # sits beside it. Muse put it inside `answer` four times across one evening,
    # separated by context resets and by dozens of submissions that got it right
    # — so this is not a worker failing to learn, it is a shape that a worker
    # regresses to whenever it stops remembering. Accept it in the place three
    # different sessions reached for, and keep the refusal for anything else.
    #
    # The explicit argument still wins: a caller that sends both meant the one it
    # put where the schema asked for it.
    def lift_searched(answer)
      return [ answer, nil ] unless answer.is_a?(Hash) && answer.key?("searched")

      [ answer.except("searched"), answer["searched"] ]
    end

    def unknown_sections(unknown)
      message = "unknown answer sections: #{unknown.join(', ')}"
      misplaced = unknown & MISPLACED
      return "#{message}. The answer takes #{SECTIONS.join(', ')}." if misplaced.empty?

      one = misplaced.one?
      "#{message}. #{misplaced.to_sentence} #{one ? 'is an argument' : 'are arguments'} of submit_task itself, " \
        "beside answer and not inside it: submit_task(task_id:, outcome:, #{misplaced.first}: \"...\", answer: { ... })."
    end

    def ops_for(task, answer)
      answer = {} if answer.nil?
      raise ArgumentError, "answer must be an object with any of #{SECTIONS.join(', ')}" unless answer.is_a?(Hash)
      unknown = answer.keys.map(&:to_s) - SECTIONS
      raise ArgumentError, unknown_sections(unknown) if unknown.any?

      target = task.target_type == "CLAIM" ? task.target_id : nil
      location = task.packet.dig("context", "source_location_id")
      claim_ref = ->(h) { h == "target" ? target : h }
      # "packet" means the passage the task handed you, and only a task that
      # carries one has it: EVIDENCE_VERIFICATION does, QUALIFIER_CHECK does not.
      # It used to resolve to nil there and fail downstream as "expected a UUID",
      # which sent a caller looking for a malformed id it had never sent.
      excerpt_ref = lambda do |h|
        next h unless h == "packet"
        if location.nil?
          raise ArgumentError, "this #{task.task_type} carries no passage of its own, so excerpt: \"packet\" refers to nothing. " \
                               "Cite a source_location_id from the claim's counted evidence, or add an excerpt of your own."
        end
        location
      end
      # The packet's own passage is cited as "packet" and never appears in the
      # answer's excerpts, so its kind has to come from the location itself for
      # the transcription rule to weigh it as record_investigation would. Read
      # from the row, never from the packet's contributor-supplied locator.
      packet_kinds = { "packet" => (SourceLocation.find_by(id: location)&.locator_type if location) }.compact
      ops = []
      section(answer, "sources").each do |s|
        ops << { "op" => "CREATE_SOURCE", "ref" => handle!(s), "source_type" => s["type"], "title" => s["title"], "canonical_uri" => s["url"], "publisher" => s["publisher"],
                 "creator" => s["creator"], "publication_date" => s["publication_date"], "retrieved_at" => s["retrieved_at"] }.compact
      end
      section(answer, "excerpts").each do |e|
        text = e["text"]
        ops << { "op" => "CREATE_SOURCE_LOCATION", "ref" => handle!(e), "source_id" => e["source"], "locator_type" => e.fetch("kind", "QUOTE"), "locator" => e.fetch("locator", {}),
                 "excerpt" => text, "excerpt_hash" => (Crypto::Hashing.bytes(text) if text.is_a?(String)) }.compact
      end
      section(answer, "claims").each do |c|
        op = { "op" => "CREATE_CLAIM", "ref" => handle!(c), "canonical_text" => c["text"], "claim_type" => c["type"], "affirms_not_private_individual" => true, "qualifiers" => c.fetch("qualifiers", {}) }
        op["section_id"] = task.section_id if task.task_type == "CLAIM_EXTRACTION" && task.section_id # Stage 21: born in the leaf
        ops << op
      end
      section(answer, "edges").each do |e|
        ops << { "op" => "CREATE_CLAIM_EDGE", "from_claim_id" => claim_ref.call(e["from"]), "to_claim_id" => claim_ref.call(e["to"]), "relationship_type" => e.fetch("type", "NARROWS") }
      end
      section(answer, "evidence").each do |ev|
        ops << { "op" => "CREATE_EVIDENCE", "ref" => handle!(ev), "source_location_id" => excerpt_ref.call(ev["excerpt"]), "observation_type" => ev.fetch("observation_type", "DIRECT_TEXT"), "statement" => ev["statement"] }
      end
      section(answer, "links").each do |l|
        ops << { "op" => "LINK_EVIDENCE", "evidence_item_id" => l["evidence"], "claim_id" => claim_ref.call(l["claim"]), "direction" => l["direction"],
                 "relevance_strength" => l.fetch("strength", "DIRECT"), "interpretive_steps" => Investigations::Steps.for_link(l, answer, known_kinds: packet_kinds), "note" => l["note"] }.compact
      end
      section(answer, "groups").each do |g|
        handle = handle!(g)
        ops << { "op" => "CREATE_INDEPENDENCE_GROUP", "ref" => handle, "group_type" => g.fetch("type", "OTHER"), "description" => g["description"] }.compact
        Array(g["members"]).each { |m| ops << { "op" => "ASSIGN_INDEPENDENCE_GROUP", "evidence_item_id" => m, "independence_group_id" => handle } }
      end
      section(answer, "inferences").each do |inf|
        conclusion = inf["conclusion"] == "target" && task.target_type == "INFERENCE" ? Inference.find(task.target_id).conclusion_claim_id : claim_ref.call(inf["conclusion"])
        ops << { "op" => "CREATE_INFERENCE", "ref" => handle!(inf), "conclusion_claim_id" => conclusion,
                 "premises" => Array(inf["premises"]).map { |p| { "claim_id" => claim_ref.call(p["claim"]), "polarity" => p.fetch("polarity", "HOLDS") } },
                 "inference_type" => inf.fetch("type", "DEDUCTIVE"), "rule" => inf["rule"], "strength" => inf.fetch("strength", "SUPPORTS"), "affirms_not_private_individual" => true }.compact
      end
      section(answer, "supersede").each do |s|
        ops << { "op" => "SUPERSEDE_LINK", "link_id" => s["link_id"], "direction" => s["direction"], "relevance_strength" => s.fetch("strength", "DIRECT"),
                 "interpretive_steps" => s.fetch("steps", 0), "reason" => s["reason"] }.compact
      end
      ops
    end

    def section(answer, key)
      list = answer.fetch(key, [])
      raise ArgumentError, "#{key} must be an array of objects" unless list.is_a?(Array) && list.all?(Hash)

      list
    end

    def handle!(item)
      handle = item["handle"]
      return nil if handle.nil? && !item.key?("members")
      raise ArgumentError, "handle #{handle.inspect} must match #{HANDLE.source} and not be #{RESERVED.join(' or ')}" unless handle.is_a?(String) && HANDLE.match?(handle) && !RESERVED.include?(handle)

      handle
    end
  end
end
