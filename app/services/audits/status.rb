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

    def compute_confirmed?(contribution_id, seq)
      # :contribution as well: the principal is read off it for every audit.
      audits = Audit.active_at(seq).where(target_contribution_id: contribution_id, result: "CONFIRMED").includes(:auditor, :contribution)
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

      !Audit.active_at(seq).where(target_contribution_id: contribution.id, result: "CONFIRMED").where("created_seq > ?", challenge_seq).exists?
    end

    def challenge_seq_for(contribution, seq)
      revocation = Contribution.where(action_type: "REVOKE_KEY").where("seq <= ?", seq)
                               .where("payload->>'key_id' = ?", contribution.signer_key_id)
                               .where("(payload->>'compromised_since')::bigint <= ?", contribution.seq).order(:seq).first
      unresolved = Audit.active_at(seq).where(target_contribution_id: contribution.id).order(created_seq: :desc).first
      candidates = []
      candidates << revocation.seq if revocation && revocation.seq > contribution.seq
      candidates << unresolved.created_seq if unresolved&.result == "UNRESOLVED"
      candidates.max
    end

    def latest_audit(contribution_id, seq)
      Audit.active_at(seq).where(target_contribution_id: contribution_id).order(created_seq: :desc).first
    end
  end
end
