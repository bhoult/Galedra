# frozen_string_literal: true

module Ledger
  # The closed list of contribution action types (spec 02 §3.6) and their
  # class (02 §1.1a). Control contributions take effect on append when the
  # signer is authorized; epistemic ones are projected with accepted_seq null.
  module ActionTypes
    CONTROL = %w[
      REGISTER_KEY DELEGATE REVOKE_KEY REVOKE_DELEGATION ADOPT_KEY
      ACCEPT INVALIDATE AUDIT QUARANTINE RELEASE_QUARANTINE TAKEDOWN
      RELEASE_SCORING_MODEL AMEND_CONSTITUTION RETRIEVE_SOURCE
    ].freeze

    EPISTEMIC = %w[
      CREATE_SOURCE CREATE_SOURCE_LOCATION CREATE_CLAIM SUPERSEDE_CLAIM SET_TRUTH_EVALUABLE
      CREATE_EVIDENCE LINK_EVIDENCE CREATE_CLAIM_EDGE CREATE_INDEPENDENCE_GROUP
      ASSIGN_INDEPENDENCE_GROUP SUPERSEDE_LINK MERGE_CLAIMS TASK_RESULT TAG_CLAIM
      CREATE_SECTION PLACE_CLAIM
    ].freeze

    ALL = (CONTROL + EPISTEMIC).freeze

    # Types whose server-side handling exists yet. Others are rejected with
    # UNSUPPORTED_ACTION rather than logged unchecked. AMEND_CONSTITUTION
    # arrives with the amendment process.
    IMPLEMENTED = (%w[REGISTER_KEY DELEGATE REVOKE_KEY REVOKE_DELEGATION ADOPT_KEY ACCEPT INVALIDATE QUARANTINE RELEASE_QUARANTINE TAKEDOWN
                       RELEASE_SCORING_MODEL AUDIT RETRIEVE_SOURCE] + EPISTEMIC).freeze

    def self.class_for(type)
      CONTROL.include?(type) ? Contribution::CONTROL : Contribution::EPISTEMIC
    end

    def self.supported?(type)
      IMPLEMENTED.include?(type)
    end
  end
end
