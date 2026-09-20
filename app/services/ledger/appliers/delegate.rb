# frozen_string_literal: true

module Ledger
  module Appliers
    # DELEGATE (spec 02 §3.1, 05 §4): a human principal grants an agent key
    # permission for task types and domains until valid_until.
    module Delegate
      extend Checks

      def self.authorize!(validated)
        signer = validated.contributor
        reject("NOT_AUTHORIZED", "$.signer_key_id", "only a HUMAN contributor may delegate") unless signer&.human?

        payload = validated.payload
        delegate = Contributor.find_by(key_id: payload["delegate_key_id"].to_s)
        reject("DELEGATE_UNKNOWN", "$.payload.delegate_key_id", "no registered contributor has this key") if delegate.nil?
        reject("DELEGATE_INVALID", "$.payload.delegate_key_id", "delegate must be an AGENT key") unless delegate.agent?
        reject("DELEGATE_INVALID", "$.payload.delegate_key_id", "delegate key is revoked") if delegate.revoked?

        permissions = payload["permissions"]
        reject("SCHEMA_INVALID", "$.payload.permissions", "expected an object") unless permissions.is_a?(Hash)
        %w[allowed_task_types domains].each do |key|
          list = permissions[key]
          reject("SCHEMA_INVALID", "$.payload.permissions.#{key}", "expected an array of strings") unless list.is_a?(Array) && list.all?(String)
        end
        # Delegations signed before the cap became hourly carry max_tasks_per_day.
        # Both keys are accepted so replay reproduces those rows exactly; a
        # payload may not carry both, which would leave the limit ambiguous.
        if payload.key?("max_tasks_per_hour") && payload.key?("max_tasks_per_day")
          reject("SCHEMA_INVALID", "$.payload.max_tasks_per_hour", "carries both max_tasks_per_hour and max_tasks_per_day; only one may be given")
        end
        integer_or_nil!(payload, payload.key?("max_tasks_per_day") ? "max_tasks_per_day" : "max_tasks_per_hour")
        from = time!(payload, "valid_from")
        to = time!(payload, "valid_until")
        reject("SCHEMA_INVALID", "$.payload.valid_until", "must be after valid_from") unless to > from
      end

      def self.apply(contribution)
        payload = contribution.payload
        delegate = Contributor.find_by!(key_id: payload["delegate_key_id"])
        AgentDelegation.create!(
          id: Ids.derive(contribution.id, "delegation"),
          principal_contributor_id: contribution.contributor_id,
          delegate_contributor_id: delegate.id,
          permissions: payload["permissions"],
          max_tasks_per_hour: payload["max_tasks_per_hour"] || payload["max_tasks_per_day"],
          valid_from: Time.iso8601(payload["valid_from"]),
          valid_until: Time.iso8601(payload["valid_until"]),
          delegation_signature: contribution.signature,
          created_seq: contribution.seq
        )
      end
    end
  end
end
