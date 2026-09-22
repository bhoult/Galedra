# frozen_string_literal: true

module Scoring
  # Bulk loads for one whole-graph scoring pass
  # (docs/profiler/2026-09-19-weaknesses-at-3000-claims.md, finding 5 and its
  # follow-up). `Scoring::BuildInput` asks, for every counted link on every
  # claim: is this source quarantined, is this link challenged, is it
  # audit-confirmed. Each was its own statement, multiplied by links, then
  # claims, then released models — about 24 statements a claim, flat as the
  # corpus grows, so a cold report over 3,000 claims is on the order of 220,000.
  #
  # The same block-scoped thread-local shape as `Audits::Status.memoized`, and
  # for the same reason: the answers are a function of the log up to a seq, and
  # the log does not move while a pass runs. Keyed by seq so nothing outlives
  # the snapshot it was true for, cleared on the way out so nothing leaks into
  # another request, and absent entirely outside a pass — every lookup here
  # falls back to the query it replaces. This changes how often a question is
  # asked, never the answer (Invariant 4).
  #
  # What is deliberately NOT batched: an evidence item's independence group.
  # That reads `order(accepted_seq: :desc).first`, and two assignments accepted
  # at one seq would be a tie SQL breaks arbitrarily, so grouping a single
  # sorted query could pick a different row and move a trace. Audits cannot tie
  # — one audit per contribution, one contribution per seq, so `created_seq` is
  # unique — and neither can revocations, which are ordered by `seq`.
  module Pass
    KEY = :galedra_scoring_pass

    module_function

    # `down_to` (Stage 38): the oldest seq this pass may answer for. A claim is
    # scored at its own watermark, which is at or before the seq the pass was
    # built at, and everything held here — quarantines on its sources, audits on
    # its link entries, revocations of their signers — would have moved that
    # watermark had it changed in between. So one load still serves the set.
    # The default is the seq itself, which is the old behaviour exactly.
    def over(claims, seq, down_to: seq)
      outermost = Thread.current[KEY].nil?
      Thread.current[KEY] ||= build(Array(claims), seq).merge(down_to: down_to)
      yield
    ensure
      Thread.current[KEY] = nil if outermost
    end

    # nil means "not in a pass, or a pass that cannot answer for this seq": ask
    # the database.
    def store(seq)
      s = Thread.current[KEY]
      s if s && seq <= s[:seq] && seq >= s.fetch(:down_to, s[:seq])
    end

    def quarantined_sources(seq) = store(seq)&.fetch(:quarantined_sources)

    # nil, not [], for a key the pass does not hold. [] is a definite answer —
    # "this entry has no audits" — and returning it for something merely absent
    # from the bulk load skips the database fallback and reports a link
    # unaudited, unchallenged and un-revoked: a value that was never true at any
    # seq (code review, 2026-09-22).
    #
    # The pass is built from the links effective at the seq it was built at,
    # while `down_to` lets it answer for the earlier seq a claim is scored at.
    # A link effective then and superseded since is absent from the map, and it
    # is exactly the case these two got wrong. `quarantined_sources` above has
    # always returned nil for the same reason.
    # A pass that loaded a key answers for it, with [] meaning "none" — that is
    # the batching win and it stays. A key it never loaded gets nil, so the
    # caller asks the database.
    def audits_for(contribution_id, seq)
      answer(store(seq), :audit_targets, :audits_by_target, contribution_id)
    end

    def revocations_for(key_id, seq)
      answer(store(seq), :revocation_keys, :revocations_by_key, key_id)
    end

    def answer(store, covered, map, key)
      return nil if store.nil? || !store.fetch(covered).include?(key)

      store.fetch(map).fetch(key, [])
    end

    def build(claims, seq)
      ids = claims.map(&:id)
      return empty(seq) if ids.empty?

      links = EvidenceClaimLink.effective_at(seq).where(claim_id: ids)
                               .includes(:contribution, evidence_item: { source_location: :source }).to_a
      sources = links.filter_map { |l| l.evidence_item&.source_location&.source_id }.uniq
      contributions = links.filter_map(&:contribution).uniq
      {
        seq: seq,
        quarantined_sources: Quarantine.active_at(seq).where(target_type: "SOURCE", target_id: sources).pluck(:target_id).to_set,
        # What was loaded, so "absent from the map" can be told from "has none".
        # Without this the pass answered [] for a link it never loaded — one
        # effective at the seq a claim is scored at but superseded by the seq the
        # pass was built at — and reported it unaudited (code review).
        audit_targets: contributions.map(&:id).to_set,
        revocation_keys: contributions.filter_map(&:signer_key_id).uniq.to_set,
        audits_by_target: audits(contributions.map(&:id), seq),
        revocations_by_key: revocations(contributions.filter_map(&:signer_key_id).uniq, seq)
      }
    end

    def empty(seq)
      { seq: seq, quarantined_sources: Set.new, audit_targets: Set.new, revocation_keys: Set.new,
        audits_by_target: {}, revocations_by_key: {} }
    end

    # Ordered newest first, as `challenge_seq_for` and `latest_audit` read them.
    def audits(contribution_ids, seq)
      return {} if contribution_ids.empty?

      Audit.active_at(seq).where(target_contribution_id: contribution_ids)
           .includes(:auditor, :contribution).order(created_seq: :desc).group_by(&:target_contribution_id)
    end

    # Oldest first, as `challenge_seq_for` reads them (`order(:seq).first`).
    def revocations(key_ids, seq)
      return {} if key_ids.empty?

      Contribution.where(action_type: "REVOKE_KEY").where("seq <= ?", seq)
                  .where("payload->>'key_id' IN (?)", key_ids).order(:seq)
                  .group_by { |c| c.payload["key_id"] }
    end
  end
end
