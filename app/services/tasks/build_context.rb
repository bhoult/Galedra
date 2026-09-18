# frozen_string_literal: true

module Tasks
  # The context compiler (spec 04 §5): deterministic, no LLM. Same inputs give
  # the same packet bytes apart from task id, issued_at, and the signature.
  # Contributor notes are never included; excerpts are labelled untrusted and
  # capped; scores and identities stay out.
  module BuildContext
    module_function

    def call(task_type:, target_id:, snapshot_seq:, token_budget: Types::DEFAULT_TOKEN_BUDGET, location_id: nil, domain: Audits::Policy.default_domain)
      spec = Types.spec(task_type)
      target, context = send("context_for_#{task_type.downcase}", target_id, snapshot_seq, location_id, token_budget)
      {
        "protocol" => Packet::PROTOCOL,
        "task_type" => task_type,
        "domain" => domain,
        "snapshot_seq" => snapshot_seq,
        "target" => target,
        "objective" => spec[:objective],
        "context" => context,
        "constraints" => { "allowed_ops" => spec[:allowed_ops], "max_ops" => spec[:max_ops], "require_exact_location" => task_type == "EVIDENCE_VERIFICATION" },
        "return_schema" => Packet::RESULT_PROTOCOL,
        "server_key_id" => Crypto::SystemKey.key_id
      }
    end

    def claim_target(claim)
      { "claim_id" => claim.id, "claim_text" => claim.canonical_text, "claim_type" => claim.claim_type }
    end

    def excerpt(text)
      text.to_s[0, Types::EXCERPT_CAP]
    end

    def counted_items(claim, seq)
      claim.evidence_claim_links.effective_at(seq).includes(evidence_item: { source_location: :source }).order(:id).map do |link|
        [ link, link.evidence_item, link.evidence_item.source_location ]
      end
    end

    def context_for_evidence_verification(claim_id, seq, location_id, _budget)
      claim = Claim.find(claim_id)
      location = SourceLocation.find(location_id)
      [ claim_target(claim), {
        "source_id" => location.source_id, "source_location_id" => location.id,
        "locator" => { "type" => location.locator_type }.merge(location.locator),
        "untrusted_excerpt" => excerpt(location.excerpt), "excerpt_hash" => location.excerpt_hash,
        "known_qualifiers" => claim.qualifiers
      } ]
    end

    def context_for_opposing_evidence_search(claim_id, seq, _location_id, _budget)
      claim = Claim.find(claim_id)
      model = Scoring::Registry.default_model_at(seq)
      result = model && Scoring::Score.call(claim, seq, model)
      state = result&.assessment_state || "INSUFFICIENT_EVIDENCE"
      direction = %w[SUPPORTED LEANS_SUPPORTED].include?(state) ? "CONTRADICT" : "SUPPORT"
      current_side = direction == "CONTRADICT" ? "SUPPORT" : "CONTRADICT"
      items = counted_items(claim, seq)
      [ claim_target(claim), {
        "search_direction" => direction,
        "current_state" => state,
        "current_counted_statements" => items.select { |l, _, _| l.direction == current_side }.map { |_, e, _| e.statement.to_s },
        "exclude_lineage_keys" => items.filter_map { |_, _, loc| loc.source.lineage_key }.uniq.sort,
        "scope" => "any source you can cite exactly; new sources are stored metadata-only until a human imports them"
      } ]
    end

    def context_for_source_independence_check(claim_id, seq, _location_id, _budget)
      claim = Claim.find(claim_id)
      items = counted_items(claim, seq).map do |_, item, loc|
        {
          "evidence_item_id" => item.id, "statement" => item.statement, "independence_group_id" => item.independence_group_at(seq)&.id,
          "source" => { "source_id" => loc.source_id, "title" => loc.source.title, "creator" => loc.source.creator, "publisher" => loc.source.publisher,
                        "publication_date" => loc.source.publication_date&.iso8601, "source_type" => loc.source.source_type, "lineage_key" => loc.source.lineage_key },
          "untrusted_excerpt" => excerpt(loc.excerpt)
        }
      end
      groups = IndependenceGroup.counted_at(seq).where(id: items.filter_map { |i| i["independence_group_id"] }).order(:id)
      [ claim_target(claim), { "counted_evidence" => items,
                               "existing_groups" => groups.map { |g| { "independence_group_id" => g.id, "group_type" => g.group_type, "description" => g.description } } } ]
    end

    def context_for_qualifier_check(claim_id, seq, _location_id, _budget)
      claim = Claim.find(claim_id)
      items = counted_items(claim, seq).map do |link, item, loc|
        { "link_id" => link.id, "direction" => link.direction, "relevance_strength" => link.relevance_strength, "interpretive_steps" => link.interpretive_steps,
          "evidence_item_id" => item.id, "statement" => item.statement, "source_location_id" => loc.id, "source_id" => loc.source_id,
          "source_type" => loc.source.source_type, "untrusted_excerpt" => excerpt(loc.excerpt) }
      end
      candidates = Claims::Duplicates.candidates(claim.canonical_text, exclude_id: claim.id, limit: 5)
                                     .select { |c| c.created_seq <= seq }
                                     .map { |c| { "claim_id" => c.id, "claim_text" => c.canonical_text, "claim_type" => c.claim_type } }
      [ claim_target(claim), { "known_qualifiers" => claim.qualifiers, "counted_links" => items, "candidate_claims" => candidates,
                               "qualifier_kinds" => %w[time_range population denominator baseline sampling jurisdiction translation] } ]
    end

    def context_for_claim_extraction(source_id, seq, location_id, budget)
      source = Source.find(source_id)
      locations = location_id ? [ SourceLocation.find(location_id) ] : source.source_locations.active_at(seq).order(:created_seq).to_a
      excerpts = locations.map { |l| { "source_location_id" => l.id, "locator" => { "type" => l.locator_type }.merge(l.locator), "untrusted_excerpt" => excerpt(l.excerpt) } }
      excerpts = [ { "source_location_id" => nil, "untrusted_excerpt" => excerpt(source.content) } ] if excerpts.empty?
      [ { "source_id" => source.id, "title" => source.title, "source_type" => source.source_type }, {
        "excerpts" => excerpts.first([ budget / 500, 1 ].max),
        "claim_types" => Claim::TYPES,
        "atomicity_rules" => "One minimal proposition per claim. Split compound assertions whose parts could differ in evidential support. Keep what a text says (TEXTUAL) separate from whether it is true, and causal, normative, and rhetorical content separate from observations.",
        "required_fields" => %w[canonical_text claim_type affirms_not_private_individual]
      } ]
    end
  end
end
