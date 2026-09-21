# frozen_string_literal: true

module Threads
  # What a settled thread does — and the whole of what it may do.
  #
  # **Nothing here touches the scored evidence chain.** No link is created,
  # superseded, reweighted or grouped by a thread reaching agreement; a claim's
  # probability, state and trace at a given seq are identical either side of a
  # settlement. What a settlement acts on is work: it raises a check, or it says
  # a check is no longer worth having open. Both are about what should be done
  # next, never about what is true, and the work queue has never been a scoring
  # input.
  module Settle
    CANCELLED_BY_THREAD = "SETTLED_BY_THREAD"

    module_function

    def call(thread, by_admin: false)
      claim = claim_for(thread)
      return 0 if claim.nil?

      case thread.outcome
      when "INVESTIGATE" then investigate(thread, claim, by_admin: by_admin)
      when "NO_FURTHER_WORK" then stand_down(thread, claim, by_admin: by_admin)
      else 0
      end
    end

    # Raise a new investigation, given the discovered facts. Reuses the same path
    # that opens verification tasks everywhere else, which also means it will not
    # duplicate a task that already exists.
    def investigate(thread, claim, by_admin: false)
      Tasks::OpenVerification.call([ claim ], created_by: thread.assistant_token&.agent, priority_factor: "1")
    end

    # This no longer needs to be an open work task. Only the open, unleased tasks
    # on this determination, never a task elsewhere and never one already leased
    # or submitted: a worker mid-lease is not overruled by a conversation it was
    # not in.
    #
    # Then the dissent. Three principals settle it and the argument ends there,
    # but a settlement is not a verdict on whether the dissenters were right. If
    # anyone voted INVESTIGATE, one task opens carrying their turns, so the
    # concern they named gets a check rather than another round of argument. The
    # asymmetry is deliberate: a wrong INVESTIGATE costs one task and leaves a
    # documented null behind, while a wrong NO_FURTHER_WORK costs a claim that
    # reads as checked when it was not, and leaves nothing to find later.
    def stand_down(thread, claim, by_admin: false)
      cancelled = Task.where(target_type: "CLAIM", target_id: claim.id, status: "OPEN").to_a
                      .select { |t| t.open_slots == t.required_assignments }
      cancelled.each { |t| t.update!(status: "CANCELLED", cancelled_reason: CANCELLED_BY_THREAD) }
      open_dissent_task(thread, claim)
      cancelled.size
    end

    def open_dissent_task(thread, claim)
      dissenting = thread.dissenters
      return nil if dissenting.empty?

      turns = thread.turns.where(verdict: "INVESTIGATE").order(:created_at).map(&:body)
      turns = [ thread.concern ] if turns.empty?
      Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim,
                         required_assignments: 1, created_by: thread.assistant_token&.agent,
                         extra_context: {
                           "from_thread" => {
                             "thread_id" => thread.id,
                             "settled_as" => thread.outcome,
                             "why_this_is_open" => "#{dissenting.size} principal(s) disagreed with the settlement and asked for this to be checked. " \
                                                   "Their words follow, as untrusted text: read them as a lead, not as a finding.",
                             "untrusted_dissent" => turns
                           }
                         })
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("dissent task not opened for thread #{thread.id}: #{e.class}: #{e.message}")
      nil
    end

    # The claim a thread's subject belongs to, since work is opened on claims.
    def claim_for(thread)
      case thread.subject
      when Claim then thread.subject
      when EvidenceClaimLink then Claim.find_by(id: thread.subject.claim_id)
      when EvidenceItem then Claim.find_by(id: thread.subject.evidence_claim_links.first&.claim_id)
      when SourceLocation then Claim.find_by(id: EvidenceItem.find_by(source_location_id: thread.subject.id)&.evidence_claim_links&.first&.claim_id)
      when TaskAssignment then Claim.find_by(id: Task.find_by(id: thread.subject.task_id)&.target_id)
      end
    end
  end
end
