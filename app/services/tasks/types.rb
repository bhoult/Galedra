# frozen_string_literal: true

module Tasks
  # The five P0 task types (spec 04 §2): allowed ops, outcomes, and whether a
  # result that only adds objects is accepted automatically (02 §1.1a).
  module Types
    SPECS = {
      "CLAIM_EXTRACTION" => {
        target_type: "SOURCE", allowed_ops: %w[CREATE_CLAIM], outcomes: %w[CLAIMS_FOUND NO_CLAIMS], max_ops: 20,
        lease_hours: 2, auto_accept: false, cost: "2",
        objective: "Extract the atomic claims the excerpt asserts. One proposition per claim, typed. Every claim must carry affirms_not_private_individual: true. Do not evaluate the claims."
      },
      "EVIDENCE_VERIFICATION" => {
        target_type: "CLAIM", allowed_ops: %w[LINK_EVIDENCE CREATE_EVIDENCE], outcomes: %w[CONFIRMED PARTIAL NOT_SUPPORTED CANNOT_DETERMINE], max_ops: 3,
        lease_hours: 2, auto_accept: true, cost: "1",
        objective: "Decide whether the excerpt directly supports the claim. Do not infer beyond the excerpt."
      },
      "OPPOSING_EVIDENCE_SEARCH" => {
        target_type: "CLAIM", allowed_ops: %w[CREATE_SOURCE CREATE_SOURCE_LOCATION CREATE_EVIDENCE LINK_EVIDENCE], outcomes: %w[FOUND NONE_FOUND], max_ops: 12,
        lease_hours: 4, auto_accept: true, cost: "3",
        objective: "Search for evidence in the stated direction. Report NONE_FOUND if none exists; a documented null search is information."
      },
      "SOURCE_INDEPENDENCE_CHECK" => {
        target_type: "CLAIM", allowed_ops: %w[CREATE_INDEPENDENCE_GROUP ASSIGN_INDEPENDENCE_GROUP], outcomes: %w[GROUPED INDEPENDENT CANNOT_DETERMINE], max_ops: 20,
        lease_hours: 2, auto_accept: true, cost: "2",
        objective: "Decide which of the counted evidence items share an upstream origin. Group dependent items; leave independent ones alone."
      },
      "INFERENCE_REVIEW" => {
        target_type: "INFERENCE", allowed_ops: %w[CREATE_CLAIM CREATE_INFERENCE CREATE_EVIDENCE LINK_EVIDENCE], outcomes: %w[VALID MISSING_PREMISE NON_SEQUITUR CANNOT_DETERMINE], max_ops: 20,
        lease_hours: 4, auto_accept: true, cost: "2",
        objective: "Decide whether the conclusion follows from the premises as stated. Name a missing premise as a new claim, or a corrected step as a new inference. Do not evaluate the premises' truth; their evidence is their own."
      },
      "QUALIFIER_CHECK" => {
        target_type: "CLAIM", allowed_ops: %w[CREATE_EVIDENCE LINK_EVIDENCE CREATE_CLAIM CREATE_CLAIM_EDGE SUPERSEDE_LINK], outcomes: %w[QUALIFIERS_FOUND NONE_MATERIAL CANNOT_DETERMINE], max_ops: 20,
        lease_hours: 4, auto_accept: true, cost: "2",
        objective: "Look for omitted time ranges, populations, denominators, baselines, sampling limits, jurisdictions, and translations in the counted evidence. Record material qualifiers as QUALIFY or CONTRADICT links, narrower claims with edges, and revised links by supersession."
      }
    }.freeze
    ALL = SPECS.keys.freeze
    MAX_OPS = 20
    DEFAULT_TOKEN_BUDGET = 2_500
    EXCERPT_CAP = 2_000

    def self.spec(task_type) = SPECS.fetch(task_type)
    def self.allowed_ops(task_type) = spec(task_type)[:allowed_ops]
    def self.lease_length(task_type) = spec(task_type)[:lease_hours].hours
  end
end
