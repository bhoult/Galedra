# frozen_string_literal: true

module Scoring
  # The highest seq at which anything that could change a claim's score moved
  # (Stage 38).
  #
  # The score cache was keyed on the exact seq it was asked for. The head seq
  # moves with every append, so any write on the node invalidated every cached
  # score on it, whether or not it bore on the claim being read. An assistant
  # working the recommended route — write evidence, read the worklist, write
  # again — invalidated its own next read every cycle, and paid 2.3 s for a page
  # it had just paid 15 ms for.
  #
  # A score at seq N is a function of a bounded set of inputs. If none of them
  # moved between N and a later seq M, the score at M *equals* the score at N.
  # So the cache is keyed on that set's high-water mark instead, and a read at M
  # reports honestly: computed at N, unchanged since N.
  #
  # **The dangerous failure is a missed input**, which would serve a stale score
  # as current, silently and indefinitely. Three things guard against it:
  #
  # 1. **An action type is either mapped or global.** `NONE` cannot touch a
  #    score, `PRECISE` names the claims it reached, and **anything else marks
  #    every claim** — which is exactly the old behaviour, so an unmapped or new
  #    action type is slow, never wrong.
  # 2. **The mapping over-approximates.** Marking a claim that did not move
  #    costs one recomputation; missing one serves a lie.
  # 3. **It is checked against the scorer, not against itself**:
  #    `spec/services/scoring/watermark_spec.rb` mutates each member of the
  #    dependency set in turn and fails if the mark does not move, and
  #    `bin/rails scores:watermarks[verify]` rescores a whole corpus both ways
  #    and compares trace hashes.
  module Watermark
    # Cannot reach `Scoring::BuildInput` at all: keys and delegations, the topic
    # vocabulary, outlines (a section's source is fixed at creation; what a
    # claim is *placed* in is PLACE_CLAIM, which is precise below), source
    # fetches, inferences, and releasing a model — which gets its own cache key
    # by being part of it.
    NONE = %w[REGISTER_KEY DELEGATE REVOKE_DELEGATION ADOPT_KEY RELEASE_SCORING_MODEL
              AMEND_CONSTITUTION TAG_CLAIM CREATE_SECTION RETRIEVE_SOURCE CREATE_INFERENCE].freeze

    # Types whose reach is known claim by claim. Everything not here and not in
    # NONE marks the whole table: REVOKE_KEY, whose compromise window can
    # challenge any link its key signed, and TAKEDOWN, whose redaction is
    # rebuilt across the graph, are both rare enough to pay for it.
    PRECISE = %w[CREATE_CLAIM SUPERSEDE_CLAIM SET_TRUTH_EVALUABLE CREATE_SOURCE CREATE_SOURCE_LOCATION
                 CREATE_EVIDENCE LINK_EVIDENCE SUPERSEDE_LINK CREATE_INDEPENDENCE_GROUP
                 ASSIGN_INDEPENDENCE_GROUP MERGE_CLAIMS PLACE_CLAIM TASK_RESULT
                 ACCEPT INVALIDATE AUDIT QUARANTINE RELEASE_QUARANTINE CREATE_CLAIM_EDGE].freeze

    module_function

    # Called by Ledger::Apply inside the append transaction, not from the
    # recompute job: a read between the append and an asynchronous job would
    # otherwise serve a score from before the write.
    def stamp!(contribution)
      type = contribution.action_type
      return 0 if NONE.include?(type)

      seq = contribution.seq
      return all!(seq) unless PRECISE.include?(type)

      ids = claim_ids(contribution)
      ids.any? ? mark(Claim.where(id: ids), seq) : 0
    end

    def all!(seq) = mark(Claim.all, seq)

    # Never moves a mark backwards: replay and a late job must both be
    # idempotent, and a lower mark would serve an older score as current.
    def mark(scope, seq)
      scope.where("scored_inputs_seq IS NULL OR scored_inputs_seq < ?", seq).update_all(scored_inputs_seq: seq)
    end

    # The seq to key the cache on when a read asks for `seq`.
    #
    # A mark ahead of the question means the claim moved after it, so there is
    # nothing to reuse and the exact seq is the key, as before. Null means a
    # claim written before this stage whose mark was never rebuilt: same answer,
    # same cost as the old code.
    #
    # The mark is read from the database rather than off the object, because a
    # Claim loaded before an append carries the mark it had then, and scoring
    # right after writing — which is what recording an investigation does — would
    # otherwise key on a mark from before its own evidence and serve a score
    # without it. The golden tables caught exactly that.
    def at(claim, seq)
      bound(marks([ claim.id ])[claim.id], seq)
    end

    def marks(claim_ids)
      Claim.where(id: claim_ids).pluck(:id, :scored_inputs_seq).to_h
    end

    # The cached rows for these claims at whatever each one's key seq is, in one
    # query. The key is decided in SQL — LEAST(mark, seq), with a null mark
    # falling back to the seq asked for — so a cache hit still costs exactly one
    # statement, as it did when the key was the seq itself. Asking Ruby first
    # would have added a round trip to every scored claim on every page.
    def hits(claim_ids, seq, model_id)
      ClaimScore.joins("JOIN claims ON claims.id = claim_scores.claim_id")
                .where(claim_id: claim_ids, scoring_model_id: model_id)
                .where("claim_scores.snapshot_seq = LEAST(COALESCE(claims.scored_inputs_seq, :seq), :seq)", seq: seq)
    end

    def bound(mark, seq)
      mark && mark <= seq ? mark : seq
    end

    # Scoring::Affected answers "which claims does this contribution change the
    # score of", and is read by the scorer itself through
    # Audits::Status.downstream_count, so its answer must not move (Invariant 4).
    # The three additions below are the watermark's own and live here: a
    # placement (which decides what counts as the claim's own origin), a task
    # result (a review check with no projection row of its own), and an edge
    # (which changes how many confirmations an audit of that claim's work
    # needs, and so the audit state of every claim sharing its link entries).
    # Each of the three is asked about this contribution *and* about the one it
    # names, because accepting, invalidating or auditing an entry changes what
    # that entry does. Accepting a placement is what caught this: the placement
    # itself marked the claim, its ACCEPT did not, and the score served between
    # them was the one from before the claim had an origin.
    def claim_ids(contribution)
      # Looked up once and handed on: Affected, the placement and edge checks
      # and the task check each fetched it again (Stage 26).
      target = target_of(contribution)
      subjects = [ contribution, target ].compact
      (Affected.claim_ids(contribution, target: target) +
        subjects.flat_map { |c| placement_claims(c) + edge_claims(c) } +
        task_claims(contribution, target) + audit_claims(subjects)).uniq
    end

    # Whether a contribution of this type can have written rows of this model:
    # a question not worth a statement when the answer is no
    # (Contribution::PROJECTIONS_BY_ACTION, held by spec/models/contribution_spec.rb).
    def may_write?(contribution, model)
      contribution.projection_tables.include?(model)
    end

    # An audit changes the score of every claim whose evidence cites the entry
    # it audited, and `Audit` is not a projection model — `projection_rows` on an
    # AUDIT contribution is empty — so accepting, invalidating or re-auditing one
    # reached no claim at all. A re-audit that overturns a confirmation flips
    # `audit_confirmed`, `provisional` and the claim's probability while marking
    # nothing, and the pre-overturn trace is then served indefinitely (code
    # review, 2026-09-22).
    def audit_claims(subjects)
      targets = subjects.filter_map { |c| c.payload["target_contribution_id"] if c.action_type == "AUDIT" && c.payload.is_a?(Hash) }
      # Only an AUDIT writes an Audit row, so only those are worth asking about.
      audits = subjects.select { |c| c.action_type == "AUDIT" }
      targets += Audit.where(contribution_id: audits.map(&:id)).pluck(:target_contribution_id) if audits.any?
      return [] if targets.empty?

      Contribution.where(id: targets.uniq).flat_map { |target| Affected.rows_claims(target) }
    end

    def placement_claims(contribution)
      return [] unless may_write?(contribution, "ClaimPlacement")

      ClaimPlacement.where(contribution_id: contribution.id).pluck(:claim_id)
    end

    # A TASK_RESULT for a check task raises review_coverage without writing a row
    # that names the claim; so does accepting, invalidating or auditing one.
    def task_claims(contribution, target = target_of(contribution))
      task_ids = [ contribution.task_id, target&.task_id ].compact
      return [] if task_ids.empty?

      # Plus the claims entangled with them: `Tasks::Checks.opposing_search_done?`
      # answers for a link entry by scanning every claim that entry reaches, so a
      # check answered on one claim can confirm an audit covering another.
      targets = Task.where(id: task_ids, target_type: "CLAIM").pluck(:target_id)
      targets + entangled(targets)
    end

    def target_of(contribution)
      key = contribution.action_type == "AUDIT" ? "target_contribution_id" : "contribution_id"
      id = contribution.payload.is_a?(Hash) ? contribution.payload[key] : nil
      id ? Contribution.find_by(id: id) : nil
    end

    def edge_claims(contribution)
      return [] unless may_write?(contribution, "ClaimEdge")

      ends = ClaimEdge.where(contribution_id: contribution.id).pluck(:from_claim_id, :to_claim_id).flatten.compact
      return [] if ends.empty?

      ends + entangled(ends)
    end

    # Claims that share an audit's fate with these ones.
    #
    # `Audits::Status.confirmed?` asks about a *contribution*, and reaches every
    # claim that contribution touches — through `Affected.claims_of`, which for
    # an evidence item is every claim linked to it, by any entry. So two claims
    # are entangled if they share a link entry **or** share an evidence item:
    # what confirms an audit for one confirms it for the other, and an edge or a
    # check that changes the audit's standing changes both scores.
    #
    # Was the contribution alone, which missed the evidence-item path entirely
    # (code review, 2026-09-22).
    def entangled(claim_ids)
      return [] if claim_ids.empty?

      links = EvidenceClaimLink.where(claim_id: claim_ids)
      entries = links.distinct.pluck(:contribution_id)
      items = links.distinct.pluck(:evidence_item_id)
      return [] if entries.empty? && items.empty?

      EvidenceClaimLink.where(contribution_id: entries).or(EvidenceClaimLink.where(evidence_item_id: items))
                       .distinct.pluck(:claim_id)
    end
  end
end
