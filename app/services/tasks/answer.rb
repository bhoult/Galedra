# frozen_string_literal: true

module Tasks
  # Stage 18: a task in plain form for a connected assistant, and its answer in
  # the investigation vocabulary (handles, not refs) translated into the
  # ordered TASK_RESULT ops. Every 04 §6 check still runs in the applier; this
  # only spares the assistant refs, packet hashes, and signing.
  module Answer
    HANDLE = /\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/
    RESERVED = %w[target packet].freeze
    SECTIONS = %w[sources excerpts claims edges evidence links groups supersede].freeze

    ANSWER_WITH = {
      "EVIDENCE_VERIFICATION" =>
        "Read only the passage in context.untrusted_excerpt. Decide whether it directly bears on the claim. If it does, answer with evidence: [{handle, excerpt: \"packet\", statement}] and links: [{evidence, claim: \"target\", direction, strength, steps}]. Outcome CONFIRMED (the passage directly supports the claim), PARTIAL, NOT_SUPPORTED, or CANNOT_DETERMINE. Add no sources here.",
      "OPPOSING_EVIDENCE_SEARCH" =>
        "Search for evidence in context.search_direction; sources already counted are listed so you look elsewhere. Read what you find yourself. Answer FOUND with sources: [{handle, type, title, url, retrieved_at}], excerpts: [{handle, source, text, kind}], evidence: [{handle, excerpt, statement}], links: [{evidence, claim: \"target\", direction, strength, steps}]. Answer NONE_FOUND with an empty answer when a real search found nothing; that is a result, not a failure.",
      "SOURCE_INDEPENDENCE_CHECK" =>
        "Decide which of context.counted_evidence share one upstream origin (same press release, dataset, primary text, author). Answer GROUPED with groups: [{handle, type, description, members: [evidence_item_id, ...]}] using the ids from the packet; INDEPENDENT with an empty answer when none share an origin; CANNOT_DETERMINE when you cannot tell.",
      "QUALIFIER_CHECK" =>
        "Look in context.counted_links for omitted time ranges, populations, denominators, baselines, sampling limits, jurisdictions, or translations. Answer QUALIFIERS_FOUND with evidence and links of direction QUALIFY or CONTRADICT on claim: \"target\", or a narrower claim in claims: [{handle, text, type}] plus edges: [{from: handle, to: \"target\", type: \"NARROWS\"}], or supersede: [{link_id, direction, strength, steps, reason}] to revise a counted link. NONE_MATERIAL with an empty answer when nothing material is missing; CANNOT_DETERMINE otherwise.",
      "CLAIM_EXTRACTION" =>
        "Split context.excerpts into atomic claims: claims: [{handle, text, type}], one assertion each, typed. Outcome CLAIMS_FOUND or NO_CLAIMS. Do not evaluate them."
    }.freeze

    RULES = "Read the sources yourself; Galedra never fetches URLs. Only quoted passages are evidence. A documented null result is a result. Never invent a source or pad an answer to have something to submit."

    module_function

    def present(task, assignment, base_url:)
      packet = task.packet
      spec = Types.spec(task.task_type)
      target_url = task.target_type == "CLAIM" ? "#{base_url}/claims/#{task.target_id}" : "#{base_url}/sources/#{task.target_id}"
      context = packet["context"]
      if task.task_type == "EVIDENCE_VERIFICATION" && (location_id = context["source_location_id"])
        finding = SourceRetrieval.latest_for(context["source_id"])&.finding_for(location_id)
        context = context.merge("retrieval" => finding && { "found" => finding, "note" => "Galedra's own fetch of the page: #{finding.downcase.tr('_', ' ')}. A fact for you to weigh, not a verdict." })
      end
      if task.section_id && (section = Section.find_by(id: task.section_id))
        context = context.merge("section" => { "id" => section.id, "path" => section.path, "url" => "#{base_url}/sections/#{section.id}",
                                               "note" => "Read this section of the source yourself, between the anchor and the next section's; the packet's excerpt is only the anchor." })
      end
      { task_id: task.id, task_type: task.task_type, domain: task.domain, objective: packet["objective"],
        target: packet["target"].merge("url" => target_url), context: context,
        outcomes: spec[:outcomes], max_items: spec[:max_ops], lease_expires_at: assignment.lease_expires_at.utc.iso8601,
        task_url: "#{base_url}/tasks/#{task.id}", answer_with: ANSWER_WITH.fetch(task.task_type), rules: RULES }
    end

    # Appends the TASK_RESULT for a leased task under the assistant's key.
    def submit(token, task, outcome:, answer:)
      ops = ops_for(task, answer)
      Assistants::Write.result(token, task, outcome: outcome.to_s, ops: ops)
    end

    def ops_for(task, answer)
      answer = {} if answer.nil?
      raise ArgumentError, "answer must be an object with any of #{SECTIONS.join(', ')}" unless answer.is_a?(Hash)
      unknown = answer.keys.map(&:to_s) - SECTIONS
      raise ArgumentError, "unknown answer sections: #{unknown.join(', ')}" if unknown.any?

      target = task.target_type == "CLAIM" ? task.target_id : nil
      location = task.packet.dig("context", "source_location_id")
      claim_ref = ->(h) { h == "target" ? target : h }
      excerpt_ref = ->(h) { h == "packet" ? location : h }
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
                 "relevance_strength" => l.fetch("strength", "DIRECT"), "interpretive_steps" => steps_for(l, answer), "note" => l["note"] }.compact
      end
      section(answer, "groups").each do |g|
        handle = handle!(g)
        ops << { "op" => "CREATE_INDEPENDENCE_GROUP", "ref" => handle, "group_type" => g.fetch("type", "OTHER"), "description" => g["description"] }.compact
        Array(g["members"]).each { |m| ops << { "op" => "ASSIGN_INDEPENDENCE_GROUP", "evidence_item_id" => m, "independence_group_id" => handle } }
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

    # A transcription is a reading, not a quotation: at least one interpretive step.
    def steps_for(link, answer)
      steps = link.fetch("steps", 0).to_i
      excerpt = answer.fetch("evidence", []).find { |e| e["handle"] == link["evidence"] }&.dig("excerpt")
      kind = answer.fetch("excerpts", []).find { |e| e["handle"] == excerpt }&.fetch("kind", "QUOTE")
      kind == "TRANSCRIPTION" ? [ steps, 1 ].max : steps
    end
  end
end
