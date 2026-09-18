# frozen_string_literal: true

module Ledger
  # One applier per implemented action type. Each responds to
  # authorize!(validated) (payload checks and authorization; raises
  # Ledger::Rejected before anything is written) and apply(contribution)
  # (writes projections inside Ledger.applying). Epistemic appliers also
  # respond to accept / invalidate / auto_accept? (see Epistemic).
  module Appliers
    REGISTRY = {
      "REGISTER_KEY" => "Ledger::Appliers::RegisterKey",
      "DELEGATE" => "Ledger::Appliers::Delegate",
      "REVOKE_KEY" => "Ledger::Appliers::RevokeKey",
      "REVOKE_DELEGATION" => "Ledger::Appliers::RevokeDelegation",
      "ACCEPT" => "Ledger::Appliers::Accept",
      "INVALIDATE" => "Ledger::Appliers::Invalidate",
      "QUARANTINE" => "Ledger::Appliers::Quarantine",
      "RELEASE_QUARANTINE" => "Ledger::Appliers::ReleaseQuarantine",
      "TAKEDOWN" => "Ledger::Appliers::Takedown",
      "RELEASE_SCORING_MODEL" => "Ledger::Appliers::ReleaseScoringModel",
      "AUDIT" => "Ledger::Appliers::Audit",
      "CREATE_SOURCE" => "Ledger::Appliers::CreateSource",
      "CREATE_SOURCE_LOCATION" => "Ledger::Appliers::CreateSourceLocation",
      "CREATE_CLAIM" => "Ledger::Appliers::CreateClaim",
      "SUPERSEDE_CLAIM" => "Ledger::Appliers::SupersedeClaim",
      "SET_TRUTH_EVALUABLE" => "Ledger::Appliers::SetTruthEvaluable",
      "CREATE_EVIDENCE" => "Ledger::Appliers::CreateEvidence",
      "LINK_EVIDENCE" => "Ledger::Appliers::LinkEvidence",
      "CREATE_CLAIM_EDGE" => "Ledger::Appliers::CreateClaimEdge",
      "CREATE_INDEPENDENCE_GROUP" => "Ledger::Appliers::CreateIndependenceGroup",
      "ASSIGN_INDEPENDENCE_GROUP" => "Ledger::Appliers::AssignIndependenceGroup",
      "SUPERSEDE_LINK" => "Ledger::Appliers::SupersedeLink",
      "MERGE_CLAIMS" => "Ledger::Appliers::MergeClaims",
      "TASK_RESULT" => "Ledger::Appliers::TaskResult"
    }.freeze

    def self.for(action_type)
      REGISTRY[action_type]&.constantize
    end

    # Shared payload checks. Each raises Ledger::Rejected with a path.
    module Checks
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      def reject(code, path, detail)
        raise Ledger::Rejected.new([ { code: code, path: path, detail: detail } ])
      end

      def path(key) = "$.payload.#{key}"

      def string!(payload, key, max: nil)
        value = payload[key]
        reject("SCHEMA_INVALID", path(key), "expected a non-empty string") unless value.is_a?(String) && value.present?
        reject("SCHEMA_INVALID", path(key), "longer than #{max} characters") if max && value.length > max
        value
      end

      def string_or_nil!(payload, key)
        value = payload[key]
        return value if value.nil? || value.is_a?(String)

        reject("SCHEMA_INVALID", path(key), "expected a string or null")
      end

      def integer_or_nil!(payload, key)
        value = payload[key]
        return value if value.nil? || value.is_a?(Integer)

        reject("SCHEMA_INVALID", path(key), "expected an integer or null")
      end

      def integer!(payload, key, range: nil)
        value = payload[key]
        reject("SCHEMA_INVALID", path(key), "expected an integer") unless value.is_a?(Integer)
        reject("SCHEMA_INVALID", path(key), "expected #{range}") if range && !range.cover?(value)
        value
      end

      def boolean!(payload, key)
        value = payload[key]
        reject("SCHEMA_INVALID", path(key), "expected true or false") unless [ true, false ].include?(value)
        value
      end

      def hash!(payload, key, default: nil)
        value = payload.fetch(key, default)
        reject("SCHEMA_INVALID", path(key), "expected an object") unless value.is_a?(Hash)
        value
      end

      def hash_or_nil!(payload, key)
        value = payload[key]
        return value if value.nil? || value.is_a?(Hash)

        reject("SCHEMA_INVALID", path(key), "expected an object or null")
      end

      def enum!(payload, key, list, default: nil)
        value = payload.fetch(key, default)
        reject("SCHEMA_INVALID", path(key), "expected one of #{list.join(', ')}") unless list.include?(value)
        value
      end

      def uuid!(payload, key)
        value = payload[key]
        reject("SCHEMA_INVALID", path(key), "expected a UUID") unless value.is_a?(String) && UUID.match?(value)
        value
      end

      def time!(payload, key)
        Time.iso8601(payload[key].to_s)
      rescue ArgumentError
        reject("SCHEMA_INVALID", path(key), "expected RFC 3339")
      end

      def time_or_nil!(payload, key)
        payload[key].nil? ? nil : time!(payload, key)
      end

      # A projection row that exists and is not invalidated.
      def live!(model, payload, key, code: "TARGET_UNKNOWN")
        id = uuid!(payload, key)
        row = model.find_by(id: id)
        reject(code, path(key), "no such #{model.model_name.human.downcase}") if row.nil?
        reject("TARGET_INVALIDATED", path(key), "#{model.model_name.human.downcase} was invalidated at seq #{row.invalidated_seq}") if row.invalidated?
        row
      end

      # A claim that can receive links and edges: live, accepted, not merged
      # or superseded.
      def current_claim!(payload, key)
        claim = live!(Claim, payload, key)
        reject("CLAIM_NOT_ACCEPTED", path(key), "claim is a proposal awaiting acceptance by a different principal") unless claim.accepted?
        reject("CLAIM_NOT_CURRENT", path(key), "claim is #{claim.status.downcase}") unless claim.status == "ACTIVE"
        claim
      end
    end

    # Defaults for epistemic appliers: rows are created with accepted_seq
    # null; ACCEPT stamps them and refreshes cached columns; INVALIDATE closes
    # their windows. auto_accept? follows spec 02 §1.1a: a human's own direct
    # contribution is accepted by the system after validation.
    module Epistemic
      include Checks

      # Direct contributions carry one op in the payload; task results apply
      # several with an index in the derived id.
      def apply(contribution)
        apply_payload(contribution, contribution.payload, nil)
      end

      def row_id(contribution, kind, index)
        Ids.derive(*[ contribution.id, kind, index ].compact)
      end

      def accept(contribution, seq)
        contribution.projection_rows.each do |row|
          row.update!(accepted_seq: seq) if row.has_attribute?(:accepted_seq)
        end
        Projections::Refresh.after(contribution)
      end

      def invalidate(contribution, seq)
        contribution.projection_rows.each { |row| row.update!(invalidated_seq: seq) }
        Projections::Refresh.after(contribution)
      end

      def auto_accept?(validated)
        validated.contributor&.human? || false
      end

      # For actions that touch other contributors' rows: accept automatically
      # only when every touched row belongs to the signer's own principal.
      def same_principal?(validated, *rows)
        signer = validated.contributor
        return false unless signer&.human?

        rows.all? { |row| row.contribution.principal_contributor_id == signer.id }
      end
    end
  end
end
