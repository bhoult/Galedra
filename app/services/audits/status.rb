# frozen_string_literal: true

module Audits
  # Audit state of a contribution as of a seq (spec 03 §2 `provisional`,
  # 05 §9–§10, 05 §4). Everything is derived from windowed rows, so history
  # answers at any seq.
  module Status
    module_function

    # Within one whole-graph pass the same contribution is asked about many
    # times: once per link that cites it, again for every released model, and
    # again for every kind of weakness that looks at it. The answer cannot
    # change inside the pass, because it is a function of the log up to a seq
    # and the log does not move while a report is being built.
    #
    # So the answers are memoised for the length of an explicit block and
    # nothing longer. Thread-local, cleared on the way out, keyed by seq as
    # well as by contribution, so no answer can outlive the snapshot it was
    # true for or leak into another request. This changes how often the
    # question is asked, never the answer (Invariant 4).
    KEY = :galedra_audit_status_memo

    def memoized
      outermost = Thread.current[KEY].nil?
      Thread.current[KEY] ||= {}
      yield
    ensure
      Thread.current[KEY] = nil if outermost
    end

    def memo(kind, id, seq)
      store = Thread.current[KEY]
      return yield if store.nil?

      key = [ kind, id, seq ]
      store.fetch(key) { store[key] = yield }
    end

    # Confirmed when enough live CONFIRMED audits from distinct principals
    # exist at the seq for the target's downstream band (05 §10).
    def confirmed?(contribution_id, seq)
      memo(:confirmed, contribution_id, seq) { compute_confirmed?(contribution_id, seq) }
    end

    # Every live audit on a target at this seq, newest first. Inside a scoring
    # pass these were loaded for the whole claim set in one query
    # (Scoring::Pass); outside one this is the query it replaces, unchanged.
    # created_seq is unique per audit — one audit per contribution, one
    # contribution per seq — so there are no ties for the grouping to break
    # differently from the per-target query.
    def target_audits(contribution_id, seq)
      Scoring::Pass.audits_for(contribution_id, seq) ||
        memo(:target_audits, contribution_id, seq) do
          Audit.active_at(seq).where(target_contribution_id: contribution_id)
               .includes(:auditor, :contribution).order(created_seq: :desc).to_a
        end
    end

    # REVOKE_KEY contributions for a signer's key at or before this seq, oldest
    # first. The compromised_since test is applied in Ruby on both paths rather
    # than in SQL on one of them, so the predicate has a single home.
    def revocations_for(contribution, seq)
      Scoring::Pass.revocations_for(contribution.signer_key_id, seq) ||
        memo(:revocations, contribution.signer_key_id, seq) do
          Contribution.where(action_type: "REVOKE_KEY").where("seq <= ?", seq)
                      .where("payload->>'key_id' = ?", contribution.signer_key_id).order(:seq).to_a
        end
    end

    def compute_confirmed?(contribution_id, seq)
      # The principal is read off each audit's contribution.
      audits = target_audits(contribution_id, seq).select { |a| a.result == "CONFIRMED" }
      return false if audits.empty?

      principals = audits.map { |a| a.contribution.principal_contributor_id || a.auditor_contributor_id }.uniq
      required, opposing = Policy.required_confirmations(downstream_count(contribution_id, seq))
      return false if principals.size < required
      return Tasks::Checks.opposing_search_done?(contribution_id, seq) if opposing

      true
    end

    # Active outgoing claim edges from the claims this contribution touches.
    def downstream_count(contribution_id, seq)
      memo(:downstream, contribution_id, seq) { compute_downstream_count(contribution_id, seq) }
    end

    def compute_downstream_count(contribution_id, seq)
      contribution = Contribution.find_by(id: contribution_id)
      return 0 if contribution.nil?

      claim_ids = Scoring::Affected.rows_claims(contribution).uniq
      ClaimEdge.counted_at(seq).where(from_claim_id: claim_ids).count
    end

    # Challenged at seq: a compromise window covers it, or its latest live
    # audit at seq is UNRESOLVED, with no later CONFIRMED audit (05 §4, §9).
    def challenged?(contribution, seq)
      memo(:challenged, contribution.id, seq) { compute_challenged?(contribution, seq) }
    end

    def compute_challenged?(contribution, seq)
      challenge_seq = challenge_seq_for(contribution, seq)
      return false if challenge_seq.nil?

      target_audits(contribution.id, seq).none? { |a| a.result == "CONFIRMED" && a.created_seq > challenge_seq }
    end

    def challenge_seq_for(contribution, seq)
      revocation = revocations_for(contribution, seq).find do |c|
        since = c.payload["compromised_since"]
        # A missing compromised_since fails the SQL cast comparison; nil.to_i
        # would silently pass it, so the absence is tested rather than coerced.
        since.present? && since.to_i <= contribution.seq
      end
      unresolved = target_audits(contribution.id, seq).first
      candidates = []
      candidates << revocation.seq if revocation && revocation.seq > contribution.seq
      candidates << unresolved.created_seq if unresolved&.result == "UNRESOLVED"
      candidates.max
    end

    def latest_audit(contribution_id, seq)
      target_audits(contribution_id, seq).first
    end
  end
end
