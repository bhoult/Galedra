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
    # Stage 21: a bundle this large without sections is a large source recorded as
    # if it were a paragraph; it is refused and pointed to create_outline.
    MAX_UNSECTIONED_CLAIMS = 40
    RECORDED_BY_REQUESTER = "RECORDED_BY_REQUESTER"

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
      share = share_for(token, bundle, claims, seq, base_url)
      ClaimReference.count!(claims.map { |c| c[:id] }, "CHECKED")
      { recorded: true, snapshot_seq: seq, contributions: count, tasks_opened: tasks, ids: ids, claims: claims, existing: with_urls(existing, base_url),
        attribution: attribution(token, base_url), share: share, share_line: share[:line] }
    end

    # The page that answers what was asked, and the one line to paste (after Stage 19).
    # Stage 21: when every claim sits under one outline, the share line is that
    # outline's counts and page, never a verdict for a speech or an episode.
    def share_for(token, bundle, claims, seq, base_url)
      roots = bundle.fetch("claims", []).map { |c| c["section"].presence && Section.find_by(id: c["section"])&.root_id }
      if roots.any? && roots.uniq.size == 1 && roots.none?(&:nil?)
        root = Section.find(roots.first)
        investigation = Investigation.create!(id: SecureRandom.uuid_v7, assistant_token: token, statement: bundle["statement"].presence,
                                              claim_ids: claims.map { |c| c[:id] }, snapshot_seq: seq, section_id: root.id)
        url = "#{base_url}/sections/#{root.id}"
        return { url: url, investigation_url: "#{base_url}/investigations/#{investigation.id}", line: outline_share_line(root, seq, url), verdict: nil,
                 note: "A section check: the share line is the whole outline's counts and page. End your reply with it on its own line, exactly as given." }
      end
      investigation = Investigation.create!(id: SecureRandom.uuid_v7, assistant_token: token, statement: bundle["statement"].presence,
                                            claim_ids: claims.map { |c| c[:id] }, snapshot_seq: seq)
      url = "#{base_url}/investigations/#{investigation.id}"
      verdict = Verdict.call(investigation.claims, seq, Scoring::Registry.default_model)
      summary = Investigation.summary(claims.map { |c| c[:card] }, verdict)
      { url: url, image_url: "#{url}/card.png", line: Investigation.share_line(url: url, **summary.except(:badge)), verdict: verdict,
        note: "End your reply with share_line on its own line, exactly as given, so the person can paste it where they were going to post." }
    end

    # Anonymous work carries an adoption link: opened while signed in, it puts
    # the work under that person's name through a public ADOPT_KEY entry.
    def attribution(token, base_url)
      if token.anonymous?
        { anonymous: true, adopt_url: Assistants::Adopt.adopt_url(token, base_url),
          note: "Recorded anonymously. To put it under your name, open adopt_url while signed in to Galedra." }
      else
        { anonymous: false, principal: token.principal.display_name }
      end
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
          if c["section"].present? && !ClaimPlacement.live.exists?(claim_id: c["attach_to"], section_id: c["section"])
            write.call("PLACE_CLAIM", { "claim_id" => c["attach_to"], "section_id" => c["section"] }, nil, nil, nil)
          end
          next
        end
        payload = { "canonical_text" => c["text"], "claim_type" => c["type"], "affirms_not_private_individual" => true, "qualifiers" => c.fetch("qualifiers", {}) }
        payload["section_id"] = c["section"] if c["section"].present?
        write.call("CREATE_CLAIM", payload, c["handle"], "claim", Claim)
        topics = Array(c["topics"]).reject(&:blank?)
        write.call("TAG_CLAIM", { "claim_id" => ids[c["handle"]], "topics" => topics }, nil, nil, nil) if topics.any?
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
      new_claims = bundle.fetch("claims", []).reject { |c| c["attach_to"] }
      claims = new_claims.map { |c| Claim.find(ids[c["handle"]]) }
      location_for = lambda do |claim|
        handle = new_claims.find { |c| ids[c["handle"]] == claim.id }&.dig("handle")
        link = bundle.fetch("links", []).find { |l| l["claim"] == handle }
        excerpt = link && bundle.fetch("evidence", []).find { |e| e["handle"] == link["evidence"] }&.dig("excerpt")
        excerpt && SourceLocation.find(ids.fetch(excerpt))
      end
      opened = Tasks::OpenVerification.call(claims, created_by: token.agent, priority_factor: factor, location_for: location_for)
      cancel_extraction_tasks(token, bundle)
      opened
    end

    # Stage 21: a leaf the outline's own principal filled directly no longer needs
    # its extraction task. Cancelling a task is not a log event.
    def cancel_extraction_tasks(token, bundle)
      section_ids = bundle.fetch("claims", []).filter_map { |c| c["section"].presence }.uniq
      section_ids.each do |section_id|
        section = Section.find_by(id: section_id)
        next if section.nil? || section.root.contribution.principal_contributor_id != token.principal_contributor_id

        Task.where(task_type: "CLAIM_EXTRACTION", section_id: section.id, status: %w[OPEN LEASED]).update_all(status: "CANCELLED", cancelled_reason: RECORDED_BY_REQUESTER)
      end
    end

    # The whole outline's counts line and its page (06 §6), never a verdict.
    def outline_share_line(root, seq, url)
      Sections::Progress.share_line(root, seq, url)
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
      unsectioned = bundle.fetch("claims", []).count { |c| c.is_a?(Hash) && c["attach_to"].nil? && c["section"].blank? }
      add.call("$.claims", "more than #{Record::MAX_UNSECTIONED_CLAIMS} new claims without sections: this is a large source; record its structure first with create_outline, then record leaf by leaf with section on each claim") if unsectioned > Record::MAX_UNSECTIONED_CLAIMS
      statement = bundle["statement"]
      add.call("$.statement", "the exact text the person wanted checked, at most #{Investigation::MAX_STATEMENT_CHARS} characters") unless statement.nil? || (statement.is_a?(String) && statement.length <= Investigation::MAX_STATEMENT_CHARS)
      raise Ledger::Rejected.new(errors) if errors.any?

      true
    end

    def check_sources(s, path, _handles, add, _bundle)
      add.call("#{path}.type", "expected one of #{Source::TYPES.join(', ')}") unless Source::TYPES.include?(s["type"])
      add.call("#{path}.title", "required") unless s["title"].is_a?(String) && s["title"].present?
      add.call("#{path}.url", "required: the link to what was read") unless s["url"].is_a?(String) && s["url"].present?
      add.call("#{path}.content_hash", "sha256:<hex> of the bytes that were read, or omit it") unless s["content_hash"].nil? || Crypto::Hashing.valid?(s["content_hash"].to_s)
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
      add.call("#{path}.section", "no such section") if c["section"].present? && !Section.live.exists?(id: c["section"].to_s)
      topics = Array(c["topics"])
      unknown = topics.reject { |t| Topics.valid?(t) }
      add.call("#{path}.topics", "not in the vocabulary: #{unknown.join(', ')}; see /api/v1/topics") if unknown.any?
      add.call("#{path}.topics", "at most #{Topics::MAX_PER_CLAIM} topics") if topics.size > Topics::MAX_PER_CLAIM
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
