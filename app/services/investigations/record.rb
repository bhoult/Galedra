# frozen_string_literal: true

module Investigations
  # One call records everything an assistant found (Stage 13): sources by
  # link and hash, excerpts, atomic claims, evidence, links, and independence
  # groups, named by local handles. The bundle is validated as a whole first,
  # then appended in dependency order inside one transaction, so a bundle
  # that fails anywhere appends nothing. New claims get verification tasks.
  module Record
    SIMILARITY_ATTACH = 0.6
    ANONYMOUS_PRIORITY_FACTOR = "1.5"
    ORDER = %w[sources excerpts claims evidence links groups].freeze

    module_function

    def call(token, bundle, base_url:)
      Validate.call(bundle)
      existing = existing_for(bundle)
      unless bundle["on_duplicate"] == "create"
        strong = existing.transform_values { |c| c.select { |x| x[:similarity] >= SIMILARITY_ATTACH } }.reject { |_, c| c.empty? }
        if strong.any?
          return { recorded: false, existing: with_urls(strong, base_url),
                   hint: "Similar accepted claims already exist. Resubmit with attach_to on those claims to add your evidence to them, or on_duplicate: \"create\" to record new claims anyway." }
        end
      end

      ids = {}
      count = 0
      Contribution.transaction do
        count = append_all(token, bundle, ids)
      end
      tasks = open_tasks(token, bundle, ids)
      seq = Contribution.maximum(:seq)
      model = Scoring::Registry.default_model
      claims = bundle.fetch("claims", []).map do |c|
        claim = Claim.find(ids[c["handle"]])
        { handle: c["handle"], id: claim.id, created: c["attach_to"].nil?, url: "#{base_url}/claims/#{claim.id}",
          card: Cards::ClaimCard.call(claim, seq, model) }
      end
      { recorded: true, snapshot_seq: seq, contributions: count, tasks_opened: tasks, ids: ids, claims: claims, existing: with_urls(existing, base_url) }
    end

    def append_all(token, bundle, ids)
      count = 0
      write = lambda do |action, payload, handle, kind, model|
        result = Assistants::Write.call(token, action, payload)
        count += 1
        ids[handle] = model.find(Ledger::Ids.derive(result.contribution.id, kind)).id if handle
        result
      end

      bundle.fetch("sources", []).each do |s|
        payload = { "source_type" => s["type"], "title" => s["title"], "canonical_uri" => s["url"], "content_hash" => s["content_hash"],
                    "retrieved_at" => s["retrieved_at"], "publisher" => s["publisher"], "creator" => s["creator"], "publication_date" => s["publication_date"] }.compact
        write.call("CREATE_SOURCE", payload, s["handle"], "source", Source)
      end
      bundle.fetch("excerpts", []).each do |e|
        payload = { "source_id" => ids.fetch(e["source"]), "locator_type" => e.fetch("kind", "QUOTE"), "locator" => e.fetch("locator", {}),
                    "excerpt" => e["text"], "excerpt_hash" => Crypto::Hashing.bytes(e["text"]) }
        write.call("CREATE_SOURCE_LOCATION", payload, e["handle"], "location", SourceLocation)
      end
      bundle.fetch("claims", []).each do |c|
        if c["attach_to"]
          ids[c["handle"]] = c["attach_to"]
          next
        end
        payload = { "canonical_text" => c["text"], "claim_type" => c["type"], "affirms_not_private_individual" => true, "qualifiers" => c.fetch("qualifiers", {}) }
        write.call("CREATE_CLAIM", payload, c["handle"], "claim", Claim)
      end
      bundle.fetch("evidence", []).each do |ev|
        payload = { "source_location_id" => ids.fetch(ev["excerpt"]), "observation_type" => ev.fetch("observation_type", "DIRECT_TEXT"), "statement" => ev["statement"] }
        write.call("CREATE_EVIDENCE", payload, ev["handle"], "evidence", EvidenceItem)
      end
      bundle.fetch("links", []).each do |l|
        payload = { "evidence_item_id" => ids.fetch(l["evidence"]), "claim_id" => ids.fetch(l["claim"]), "direction" => l["direction"],
                    "relevance_strength" => l.fetch("strength", "DIRECT"), "interpretive_steps" => steps_for(l, bundle), "note" => l["note"] }.compact
        write.call("LINK_EVIDENCE", payload, nil, nil, nil)
      end
      bundle.fetch("groups", []).each do |g|
        group = write.call("CREATE_INDEPENDENCE_GROUP", { "group_type" => g.fetch("type", "OTHER"), "description" => g["description"] }, g["handle"], "group", IndependenceGroup)
        group_id = ids[g["handle"]] || IndependenceGroup.find(Ledger::Ids.derive(group.contribution.id, "group")).id
        g.fetch("members", []).each do |member|
          write.call("ASSIGN_INDEPENDENCE_GROUP", { "evidence_item_id" => ids.fetch(member), "independence_group_id" => group_id }, nil, nil, nil)
        end
      end
      count
    end

    # A transcription is a reading, not a quotation: at least one interpretive step.
    def steps_for(link, bundle)
      steps = link.fetch("steps", 0).to_i
      excerpt_handle = bundle.fetch("evidence", []).find { |e| e["handle"] == link["evidence"] }&.dig("excerpt")
      kind = bundle.fetch("excerpts", []).find { |e| e["handle"] == excerpt_handle }&.fetch("kind", "QUOTE")
      kind == "TRANSCRIPTION" ? [ steps, 1 ].max : steps
    end

    def existing_for(bundle)
      bundle.fetch("claims", []).reject { |c| c["attach_to"] }.to_h do |c|
        [ c["handle"], Claims::Duplicates.candidates(c["text"]).map { |x| { id: x.id, text: x.canonical_text, similarity: x.similarity.to_f.round(2) } } ]
      end
    end

    def with_urls(existing, base_url)
      existing.transform_values { |list| list.map { |x| x.merge(url: "#{base_url}/claims/#{x[:id]}") } }
    end

    def open_tasks(token, bundle, ids)
      factor = token.anonymous? ? ANONYMOUS_PRIORITY_FACTOR : "1"
      opened = 0
      bundle.fetch("claims", []).each do |c|
        next if c["attach_to"]

        claim = Claim.find(ids[c["handle"]])
        %w[OPPOSING_EVIDENCE_SEARCH QUALIFIER_CHECK].each do |type|
          Tasks::Create.call(task_type: type, target: claim, created_by: token.agent, priority_factor: factor)
          opened += 1
        end
        link = bundle.fetch("links", []).find { |l| l["claim"] == c["handle"] }
        excerpt = link && bundle.fetch("evidence", []).find { |e| e["handle"] == link["evidence"] }&.dig("excerpt")
        next if excerpt.nil?

        Tasks::Create.call(task_type: "EVIDENCE_VERIFICATION", target: claim, location: SourceLocation.find(ids.fetch(excerpt)), created_by: token.agent, priority_factor: factor)
        opened += 1
      end
      opened
    end
  end

  # Structural validation of a bundle before anything is appended. The
  # appliers do the deeper checks; if one of those fails the transaction rolls
  # back, so the log never holds half a bundle.
  module Validate
    module_function

    def call(bundle)
      errors = []
      add = ->(path, detail) { errors << { code: "SCHEMA_INVALID", path: path, detail: detail } }
      add.call("$", "expected an object") && (raise Ledger::Rejected.new(errors)) unless bundle.is_a?(Hash)
      handles = {}
      Record::ORDER.each do |section|
        list = bundle.fetch(section, [])
        add.call("$.#{section}", "expected an array") && next unless list.is_a?(Array)
        list.each_with_index do |item, i|
          path = "$.#{section}[#{i}]"
          add.call(path, "expected an object") && next unless item.is_a?(Hash)
          if section != "links"
            handle = item["handle"]
            add.call("#{path}.handle", "expected a unique string handle") if !handle.is_a?(String) || handle.empty? || handles.key?(handle)
            handles[handle] = section if handle.is_a?(String)
          end
          send(:"check_#{section}", item, path, handles, add, bundle)
        end
      end
      add.call("$.claims", "at least one claim is required") if bundle.fetch("claims", []).empty?
      raise Ledger::Rejected.new(errors) if errors.any?

      true
    end

    def check_sources(s, path, _handles, add, _bundle)
      add.call("#{path}.type", "expected one of #{Source::TYPES.join(', ')}") unless Source::TYPES.include?(s["type"])
      add.call("#{path}.title", "required") unless s["title"].is_a?(String) && s["title"].present?
      add.call("#{path}.url", "required: the link to what was read") unless s["url"].is_a?(String) && s["url"].present?
      add.call("#{path}.content_hash", "required: sha256:<hex> of the bytes that were read") unless Crypto::Hashing.valid?(s["content_hash"].to_s)
      add.call("#{path}.retrieved_at", "required: RFC 3339 time the source was read") unless (Time.iso8601(s["retrieved_at"].to_s) rescue nil)
    end

    def check_excerpts(e, path, handles, add, _bundle)
      add.call("#{path}.source", "must name a source handle") unless handles[e["source"]] == "sources"
      add.call("#{path}.text", "required: the exact passage") unless e["text"].is_a?(String) && e["text"].present?
      add.call("#{path}.kind", "expected QUOTE or TRANSCRIPTION") unless %w[QUOTE TRANSCRIPTION].include?(e.fetch("kind", "QUOTE"))
    end

    def check_claims(c, path, _handles, add, _bundle)
      if c["attach_to"]
        add.call("#{path}.attach_to", "no such accepted claim") unless Claim.live.accepted.exists?(id: c["attach_to"].to_s)
      else
        add.call("#{path}.text", "required: one atomic assertion") unless c["text"].is_a?(String) && c["text"].present?
        add.call("#{path}.type", "expected one of #{Claim::TYPES.join(', ')}") unless Claim::TYPES.include?(c["type"])
      end
    end

    def check_evidence(ev, path, handles, add, _bundle)
      add.call("#{path}.excerpt", "must name an excerpt handle") unless handles[ev["excerpt"]] == "excerpts"
      add.call("#{path}.statement", "required: what the passage says, in one sentence") unless ev["statement"].is_a?(String) && ev["statement"].present?
      add.call("#{path}.observation_type", "expected one of #{EvidenceItem::OBSERVATION_TYPES.join(', ')}") unless EvidenceItem::OBSERVATION_TYPES.include?(ev.fetch("observation_type", "DIRECT_TEXT"))
    end

    def check_links(l, path, handles, add, _bundle)
      add.call("#{path}.evidence", "must name an evidence handle") unless handles[l["evidence"]] == "evidence"
      add.call("#{path}.claim", "must name a claim handle") unless handles[l["claim"]] == "claims"
      add.call("#{path}.direction", "expected one of #{EvidenceClaimLink::DIRECTIONS.join(', ')}") unless EvidenceClaimLink::DIRECTIONS.include?(l["direction"])
      add.call("#{path}.strength", "expected one of #{EvidenceClaimLink::STRENGTHS.join(', ')}") unless EvidenceClaimLink::STRENGTHS.include?(l.fetch("strength", "DIRECT"))
      add.call("#{path}.steps", "expected an integer 0..#{EvidenceClaimLink::MAX_STEPS}") unless l.fetch("steps", 0).is_a?(Integer) && (0..EvidenceClaimLink::MAX_STEPS).cover?(l.fetch("steps", 0))
    end

    def check_groups(g, path, handles, add, _bundle)
      members = g.fetch("members", [])
      add.call("#{path}.members", "expected at least two evidence handles") unless members.is_a?(Array) && members.size >= 2 && members.all? { |m| handles[m] == "evidence" }
      add.call("#{path}.type", "expected one of #{IndependenceGroup::TYPES.join(', ')}") unless IndependenceGroup::TYPES.include?(g.fetch("type", "OTHER"))
    end
  end
end
