# frozen_string_literal: true

module Tasks
  # Creates a task with its signed packet and priority (spec 03 §14, 04 §3).
  module Create
    module_function

    # priority_factor (Stage 13): work from anonymous principals is checked sooner.
    # Priority is a board heuristic, never a score input.

    # A claim already scored NOT_APPLICABLE carries no probability, so the 03 §14
    # heuristic gives it maximum uncertainty and floats it to the top of the board.
    # INSUFFICIENT_EVIDENCE gets the same treatment for the same reason and deserves
    # it: evidence can settle it. This cannot — a directional state needs evidence in
    # that direction and NOT_APPLICABLE carries no probability at all (Invariant 5),
    # so a qualifier check or opposing-evidence search on one has its outcome fixed
    # before it starts. Measured on one outline: 19% of the corpus, 19% of open tasks,
    # and 38 of the top 40 by priority
    # (docs/experiments/2026-09-19-live-connector-outline.md, finding 10).
    #
    # Damped rather than closed, and outside the heuristic rather than inside it. The
    # spec's formula is untouched: this is a board factor, which the board already has.
    # The route stays open because the type is a judgement that can be revised, and a
    # check is how someone finds it was mistyped; it should simply be last rather than
    # first.
    NOT_APPLICABLE_FACTOR = "0.1"
    # `extra_context` is merged into the packet's context before it is signed, so
    # a task can carry why it exists. Stage 37's dissent task uses it: the turns
    # that argued for a check travel with the check, and a worker reads them
    # rather than finding an unexplained task on a settled question.
    def call(task_type:, target:, domain: Audits::Policy.default_domain, required_assignments: 1, location: nil, snapshot_seq: nil, created_by: nil,
             priority_factor: "1", section_id: nil, blind_requested: false, extra_context: nil)
      seq = snapshot_seq || Contribution.maximum(:seq) || 0
      spec = Types.spec(task_type)
      raise ArgumentError, "#{task_type} targets a #{spec[:target_type]}" unless target.class.name.upcase == spec[:target_type]
      raise ArgumentError, "EVIDENCE_VERIFICATION needs a source location" if task_type == "EVIDENCE_VERIFICATION" && location.nil?

      task_id = SecureRandom.uuid_v7
      packet = BuildContext.call(task_type: task_type, target_id: target.id, snapshot_seq: seq, location_id: location&.id, domain: domain)
      packet = packet.merge("task_id" => task_id, "issued_at" => Time.now.utc.iso8601)
      packet = packet.merge("context" => packet.fetch("context", {}).merge(extra_context)) if extra_context.present?
      packet = Packet.sign(packet)
      Task.create!(
        id: task_id, task_type: task_type, target_type: spec[:target_type], target_id: target.id, domain: domain,
        required_assignments: required_assignments, packet: packet, packet_hash: Packet.hash(packet), issued_seq: seq,
        priority: Scoring::Decimal.fixed(BigDecimal(priority_for(task_type, target, seq)) * BigDecimal(priority_factor.to_s), 4),
        created_by_contributor_id: created_by&.id, status: "OPEN", section_id: section_id, blind_requested: blind_requested
      )
    end

    def priority_for(task_type, target, seq)
      model = Scoring::Registry.default_model_at(seq)
      config = model&.config || Scoring::Registry.load_config(Rails.root.join("config/scoring/ledger-default-0.1.0.json"))
      if target.is_a?(Claim)
        result = model && Scoring::Score.call(target, seq, model)
        downstream = ClaimEdge.counted_at(seq).where(from_claim_id: target.id).count
        base = Priority.call(probability: result&.probability, downstream_count: downstream, review_coverage: result&.review_coverage || "0.00", task_type: task_type, config: config)
        damped(base, result)
      else
        Priority.call(probability: nil, downstream_count: 0, review_coverage: "0.00", task_type: task_type, config: config)
      end
    end

    def damped(priority, result)
      return priority unless result&.assessment_state == "NOT_APPLICABLE"

      Scoring::Decimal.fixed(BigDecimal(priority) * BigDecimal(NOT_APPLICABLE_FACTOR), 4)
    end
  end
end
