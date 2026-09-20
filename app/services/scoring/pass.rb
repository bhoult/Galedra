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

    def over(claims, seq)
      outermost = Thread.current[KEY].nil?
      Thread.current[KEY] ||= build(Array(claims), seq)
      yield
    ensure
      Thread.current[KEY] = nil if outermost
    end

    # nil means "not in a pass, or a pass at another seq": ask the database.
    def store(seq)
      s = Thread.current[KEY]
      s if s && s[:seq] == seq
    end

    def quarantined_sources(seq) = store(seq)&.fetch(:quarantined_sources)

    def audits_for(contribution_id, seq)
      store(seq)&.fetch(:audits_by_target)&.fetch(contribution_id, [])
    end

    def revocations_for(key_id, seq)
      store(seq)&.fetch(:revocations_by_key)&.fetch(key_id, [])
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
        audits_by_target: audits(contributions.map(&:id), seq),
        revocations_by_key: revocations(contributions.filter_map(&:signer_key_id).uniq, seq)
      }
    end

    def empty(seq)
      { seq: seq, quarantined_sources: Set.new, audits_by_target: {}, revocations_by_key: {} }
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
