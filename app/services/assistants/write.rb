# frozen_string_literal: true

module Assistants
  # A custodied write for a connected assistant: the server builds and signs
  # the envelope with the assistant's agent key under its delegation, names
  # the assistant in `software`, and appends through the one write path. Every
  # applier and rejection code is unchanged.
  module Write
    module_function

    def call(token, action_type, payload, task_id: nil, task_packet_hash: nil)
      raise Ledger::Rejected.new([ { code: "TOKEN_INVALID", path: "$", detail: "this assistant token is revoked or expired" } ]) unless token.usable?
      raise CapReached, "this assistant has reached its daily limit of #{token.daily_cap} writes; try again tomorrow" if token.over_daily_cap?

      envelope = Contributions::Envelope.build(
        action_type: action_type, payload: payload, key_pair: Crypto::Custody.signer_for_contributor(token.agent),
        delegation_id: token.delegation_id, software: token.software, task_id: task_id, task_packet_hash: task_packet_hash
      )
      result = Ledger::Append.call(envelope, custody: Crypto::Custody::SERVER)
      token.update_column(:last_used_at, Time.current)
      result
    end

    # A TASK_RESULT (eir-result-v1) for a task leased to the assistant's agent key (Stage 18).
    def result(token, task, outcome:, ops:)
      raise Ledger::Rejected.new([ { code: "TOKEN_INVALID", path: "$", detail: "this assistant token is revoked or expired" } ]) unless token.usable?
      raise CapReached, "this assistant has reached its daily limit of #{token.daily_cap} writes; try again tomorrow" if token.over_daily_cap?

      envelope = Contributions::Envelope.build_result(task: task, key_pair: Crypto::Custody.signer_for_contributor(token.agent), outcome: outcome, ops: ops,
                                                      delegation_id: token.delegation_id, software: token.software)
      result = Ledger::Append.call(envelope, custody: Crypto::Custody::SERVER)
      token.update_column(:last_used_at, Time.current)
      result
    end
  end
end
