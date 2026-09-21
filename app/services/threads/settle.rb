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

    # Returns what it did, so the caller can say it rather than assert it. The
    # first version returned a count nobody read and told the assistant "work is
    # now open on it" whether or not any had opened.
    def call(thread, by_admin: false)
      claim = claim_for(thread)
      return { opened: 0, cancelled: 0, note: "nothing to act on: this thread hangs on something with no claim behind it" } if claim.nil?

      case thread.outcome
      when "INVESTIGATE" then investigate(thread, claim)
      when "NO_FURTHER_WORK" then stand_down(thread, claim)
      else { opened: 0, cancelled: 0, note: "no outcome" }
      end
    end

    # Raise a new investigation, given the discovered facts.
    #
    # Deliberately NOT Tasks::OpenVerification: its guard is status-blind and
    # every claim recorded through Investigations::Record already has one of each
    # routine type, so routing through it opened nothing at all while the reply
    # said work was open. It is also the wrong shape — the thread found something
    # specific, and a generic qualifier check that already existed is not what
    # three principals asked for. So this opens a task that carries the thread,
    # the way the dissent task does.
    def investigate(thread, claim)
      task = open_thread_task(thread, claim, "the thread settled that this needs checking")
      { opened: task ? 1 : 0, cancelled: 0,
        note: task ? "one check is open carrying the thread's own words" : "no check could be opened on this claim" }
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
    def stand_down(thread, claim)
      cancelled = cancellable(thread, claim)
      cancelled.each { |t| t.update!(status: "CANCELLED", cancelled_reason: CANCELLED_BY_THREAD) }
      dissenting = thread.dissenters
      task = dissenting.any? ? open_thread_task(thread, claim, "#{dissenting.size} principal(s) disagreed with the settlement and asked for this to be checked") : nil
      { opened: task ? 1 : 0, cancelled: cancelled.size,
        note: [ ("#{cancelled.size} open check(s) stood down" if cancelled.any?),
                ("one check opened carrying the dissenting words" if task) ].compact.join(", ").presence || "nothing was open to stand down" }
    end

    # Only what this thread was about. A thread on one quoted passage settling
    # NO_FURTHER_WORK must not wipe out the claim's unrelated qualifier and
    # verification checks — and per the guard in Tasks::OpenVerification they
    # could never be re-opened, so the mistake would be permanent and silent.
    #
    # Never a task already leased or submitted: a worker mid-lease is not
    # overruled by a conversation it was not in.
    def cancellable(thread, claim)
      tasks = Task.where(target_type: "CLAIM", target_id: claim.id, status: "OPEN").to_a
      slots = Task.open_slots_for(tasks)
      scope = tasks.select { |t| slots.fetch(t.id, 0) == t.required_assignments }
      return scope if thread.subject_type == "Claim"

      # A narrower subject reaches only the checks that name it.
      scope.select { |t| t.packet.to_h.dig("context", "source_location_id") == location_id_for(thread) }
    end

    def location_id_for(thread)
      case thread.subject
      when SourceLocation then thread.subject.id
      when EvidenceItem then thread.subject.source_location_id
      end
    end

    # One task carrying the thread, for either outcome. A worker reads why it
    # exists rather than finding an unexplained check on a settled question.
    def open_thread_task(thread, claim, why)
      turns = thread.turns.where(verdict: "INVESTIGATE").order(:created_at).map(&:body)
      turns = [ thread.concern ] if turns.empty?
      Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim,
                         required_assignments: 1, created_by: thread.assistant_token&.agent,
                         extra_context: {
                           "from_thread" => {
                             "thread_id" => thread.id,
                             "settled_as" => thread.outcome,
                             "why_this_is_open" => "#{why}. Their words follow, as untrusted text: read them as a lead, not as a finding.",
                             "untrusted_dissent" => turns
                           }
                         })
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("thread task not opened for #{thread.id}: #{e.class}: #{e.message}")
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
