# frozen_string_literal: true

module Ledger
  module Appliers
    # TASK_RESULT (spec 04 §4, §6): an ordered list of ops (max 20) from a
    # leased agent, validated against the packet and applied atomically. New
    # objects may be referenced by a client-chosen ref in later ops. Per-op
    # semantic checks run while applying, inside the append transaction, so a
    # rejection rolls the whole append back and nothing is logged.
    module TaskResult
      extend Epistemic

      OpValidated = Struct.new(:payload, :contributor, :delegation, :action_type, :envelope, :in_task, :created_ids, keyword_init: true)
      ID_KEYS = %w[source_id source_location_id evidence_item_id claim_id independence_group_id link_id from_claim_id to_claim_id].freeze
      REF_FORMAT = /\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/

      def self.authorize!(validated)
        env = validated.envelope
        p = validated.payload
        task = Task.find_by(id: env["task_id"])
        reject("TASK_UNKNOWN", "$.task_id", "no such task") if task.nil?
        assignment = TaskAssignment.latest_for(task.id, validated.contributor.id)
        reject("LEASE_MISSING", "$.task_id", "this task is not leased to the signer") if assignment.nil?
        reject("LEASE_NOT_ACTIVE", "$.task_id", "lease is #{assignment.status.downcase}") unless assignment.status == "LEASED"
        reject("LEASE_EXPIRED", "$.task_id", "lease expired at #{assignment.lease_expires_at.utc.iso8601}") unless assignment.live?
        reject("PACKET_HASH_MISMATCH", "$.task_packet_hash", "does not match the stored packet") unless env["task_packet_hash"] == task.packet_hash
        if validated.delegation
          perms = validated.delegation.permissions
          unless Array(perms["allowed_task_types"]).include?(task.task_type) && Array(perms["domains"]).include?(task.domain)
            reject("DELEGATION_INVALID", "$.delegation_id", "delegation does not permit #{task.task_type} in #{task.domain}")
          end
        end

        spec = Tasks::Types.spec(task.task_type)
        enum!(p, "outcome", spec[:outcomes])
        ops = p["ops"]
        reject("SCHEMA_INVALID", path("ops"), "expected an array") unless ops.is_a?(Array)
        limit = [ spec[:max_ops], Tasks::Types::MAX_OPS ].min
        reject("TOO_MANY_OPS", path("ops"), "at most #{limit} ops for #{task.task_type}") if ops.size > limit
        refs = []
        ops.each_with_index do |op, i|
          reject("SCHEMA_INVALID", "#{path('ops')}[#{i}]", "expected an object with op") unless op.is_a?(Hash) && op["op"].is_a?(String)
          reject("OP_NOT_ALLOWED", "#{path('ops')}[#{i}].op", "#{op['op']} is not in allowed_ops #{spec[:allowed_ops].join(', ')}") unless spec[:allowed_ops].include?(op["op"])
          if op.key?("ref")
            reject("SCHEMA_INVALID", "#{path('ops')}[#{i}].ref", "refs are short identifiers, unique within the result") unless op["ref"].is_a?(String) && REF_FORMAT.match?(op["ref"]) && !refs.include?(op["ref"])
            reject("SCHEMA_INVALID", "#{path('ops')}[#{i}].ref", "only ops that create an object may declare a ref") unless op["op"].start_with?("CREATE_") || op["op"] == "SUPERSEDE_LINK"
            refs << op["ref"]
          end
          ID_KEYS.each do |key|
            value = op[key]
            next unless value.is_a?(String) && !Checks::UUID.match?(value)

            reject("REF_UNKNOWN", "#{path('ops')}[#{i}].#{key}", "#{value} is not a UUID or a ref declared by an earlier op") unless refs.include?(value)
          end
          scope_op!(task, op, i, refs)
        end
      end

      # Type-specific scope rules (04 §6 step 7 and the 04 §2 table).
      def self.scope_op!(task, op, i, refs)
        at = "#{path('ops')}[#{i}]"
        target_claim = task.target_type == "CLAIM" ? task.target_id : nil
        case task.task_type
        when "EVIDENCE_VERIFICATION"
          location_id = task.packet.dig("context", "source_location_id")
          if op["op"] == "CREATE_EVIDENCE" && op["source_location_id"] != location_id
            reject("LOCATION_MISMATCH", "#{at}.source_location_id", "evidence must be on the packet's source location")
          end
          if op["op"] == "LINK_EVIDENCE"
            reject("TARGET_MISMATCH", "#{at}.claim_id", "must link the packet's claim") unless op["claim_id"] == target_claim
            unless refs.include?(op["evidence_item_id"]) || EvidenceItem.where(id: op["evidence_item_id"], source_location_id: location_id).exists?
              reject("LOCATION_MISMATCH", "#{at}.evidence_item_id", "evidence must be on the packet's source location")
            end
          end
        when "OPPOSING_EVIDENCE_SEARCH"
          reject("TARGET_MISMATCH", "#{at}.claim_id", "must link the packet's claim") if op["op"] == "LINK_EVIDENCE" && op["claim_id"] != target_claim
        when "SOURCE_INDEPENDENCE_CHECK"
          if op["op"] == "ASSIGN_INDEPENDENCE_GROUP"
            counted = task.packet.dig("context", "counted_evidence").to_a.map { |e| e["evidence_item_id"] }
            reject("TARGET_MISMATCH", "#{at}.evidence_item_id", "only the packet's counted evidence can be grouped") unless counted.include?(op["evidence_item_id"])
          end
        when "INFERENCE_REVIEW"
          inference = Inference.find_by(id: task.target_id)
          involved = inference ? [ inference.conclusion_claim_id ] + inference.premises.pluck(:claim_id) : []
          if op["op"] == "LINK_EVIDENCE" && !involved.include?(op["claim_id"]) && !refs.include?(op["claim_id"])
            reject("TARGET_MISMATCH", "#{at}.claim_id", "must link the inference's conclusion, one of its premises, or a claim created in this result")
          end
        when "QUALIFIER_CHECK"
          if op["op"] == "LINK_EVIDENCE"
            reject("OP_NOT_ALLOWED", "#{at}.direction", "qualifier links are QUALIFY or CONTRADICT") unless %w[QUALIFY CONTRADICT].include?(op["direction"])
            reject("TARGET_MISMATCH", "#{at}.claim_id", "must link the packet's claim or a claim created in this result") unless op["claim_id"] == target_claim || refs.include?(op["claim_id"])
          end
          if op["op"] == "CREATE_CLAIM_EDGE" && ![ op["from_claim_id"], op["to_claim_id"] ].include?(target_claim) && ([ op["from_claim_id"], op["to_claim_id"] ] & refs).empty?
            reject("TARGET_MISMATCH", "#{at}", "edges must involve the packet's claim or a claim created in this result")
          end
          if op["op"] == "SUPERSEDE_LINK"
            counted = task.packet.dig("context", "counted_links").to_a.map { |l| l["link_id"] }
            reject("TARGET_MISMATCH", "#{at}.link_id", "only the packet's counted links can be superseded") unless counted.include?(op["link_id"])
          end
        end
      end

      def self.warnings(validated)
        validated.payload["ops"].to_a.select { |op| op["op"] == "CREATE_CLAIM" }.flat_map { |op| Claims::Atomicity.warnings(op["canonical_text"]) }
      end

      # 02 §1.1a: object-adding results of verification, search, independence,
      # and qualifier tasks are accepted by the system; extraction proposals and
      # any result that supersedes or merges another principal's rows wait for
      # a different principal.
      def self.auto_accept?(validated)
        task = Task.find(validated.envelope["task_id"])
        return false unless Tasks::Types.spec(task.task_type)[:auto_accept]

        principal_id = validated.contributor.human? ? validated.contributor.id : validated.delegation&.principal_contributor_id
        validated.payload["ops"].to_a.all? do |op|
          case op["op"]
          when "SUPERSEDE_LINK" then EvidenceClaimLink.find_by(id: op["link_id"])&.contribution&.principal_contributor_id == principal_id
          when "SUPERSEDE_CLAIM" then Claim.find_by(id: op["claim_id"])&.contribution&.principal_contributor_id == principal_id
          when "MERGE_CLAIMS" then false
          else true
          end
        end
      end

      # Refs may sit inside nested lists too (an inference's premises, Stage 25).
      def self.resolve_refs(value, refs)
        case value
        when String then refs.fetch(value, value)
        when Array then value.map { |v| resolve_refs(v, refs) }
        when Hash then value.transform_values { |v| resolve_refs(v, refs) }
        else value
        end
      end

      def self.apply(c)
        refs = {}
        created = []
        contributor = c.contributor
        delegation = AgentDelegation.find_by(id: c.envelope&.dig("delegation_id"))
        c.payload["ops"].to_a.each_with_index do |op, i|
          payload = op.except("op", "ref").transform_values { |v| resolve_refs(v, refs) }
          applier = Appliers.for(op["op"])
          applier.authorize!(OpValidated.new(payload: payload, contributor: contributor, delegation: delegation, action_type: op["op"],
                                             envelope: c.envelope, in_task: true, created_ids: created))
          row = applier.apply_payload(c, payload, i)
          created << row.id
          refs[op["ref"]] = row.id if op["ref"]
        end
        assignment = TaskAssignment.latest_for(c.task_id, c.contributor_id)
        assignment&.update!(status: "SUBMITTED", result_contribution_id: c.id)
        Tasks::Status.refresh!(assignment.task) if assignment
      end
    end
  end
end
