# frozen_string_literal: true

module Tasks
  # Creates a task with its signed packet and priority (spec 03 §14, 04 §3).
  module Create
    module_function

    # priority_factor (Stage 13): work from anonymous principals is checked sooner.
    # Priority is a board heuristic, never a score input.
    def call(task_type:, target:, domain: Audits::Policy.default_domain, required_assignments: 1, location: nil, snapshot_seq: nil, created_by: nil, priority_factor: "1", section_id: nil)
      seq = snapshot_seq || Contribution.maximum(:seq) || 0
      spec = Types.spec(task_type)
      raise ArgumentError, "#{task_type} targets a #{spec[:target_type]}" unless target.class.name.upcase == spec[:target_type]
      raise ArgumentError, "EVIDENCE_VERIFICATION needs a source location" if task_type == "EVIDENCE_VERIFICATION" && location.nil?

      task_id = SecureRandom.uuid_v7
      packet = BuildContext.call(task_type: task_type, target_id: target.id, snapshot_seq: seq, location_id: location&.id, domain: domain)
      packet = packet.merge("task_id" => task_id, "issued_at" => Time.now.utc.iso8601)
      packet = Packet.sign(packet)
      Task.create!(
        id: task_id, task_type: task_type, target_type: spec[:target_type], target_id: target.id, domain: domain,
        required_assignments: required_assignments, packet: packet, packet_hash: Packet.hash(packet), issued_seq: seq,
        priority: Scoring::Decimal.fixed(BigDecimal(priority_for(task_type, target, seq)) * BigDecimal(priority_factor.to_s), 4),
        created_by_contributor_id: created_by&.id, status: "OPEN", section_id: section_id
      )
    end

    def priority_for(task_type, target, seq)
      model = Scoring::Registry.default_model_at(seq)
      config = model&.config || Scoring::Registry.load_config(Rails.root.join("config/scoring/ledger-default-0.1.0.json"))
      if target.is_a?(Claim)
        result = model && Scoring::Score.call(target, seq, model)
        downstream = ClaimEdge.counted_at(seq).where(from_claim_id: target.id).count
        Priority.call(probability: result&.probability, downstream_count: downstream, review_coverage: result&.review_coverage || "0.00", task_type: task_type, config: config)
      else
        Priority.call(probability: nil, downstream_count: 0, review_coverage: "0.00", task_type: task_type, config: config)
      end
    end
  end
end
