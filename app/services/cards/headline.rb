# frozen_string_literal: true

module Cards
  # Neutral wording for assessment states (spec 06 §4 rules 10, 12): never
  # "true", "false", "debunked", or "confirmed".
  module Headline
    WORDS = {
      "SUPPORTED" => "Supported", "LEANS_SUPPORTED" => "Leans supported", "UNRESOLVED" => "Unresolved",
      "LEANS_CONTRADICTED" => "Leans contradicted", "CONTRADICTED" => "Contradicted",
      "INSUFFICIENT_EVIDENCE" => "Insufficient evidence", "NOT_APPLICABLE" => "Not assessed", "QUARANTINED" => "Quarantined"
    }.freeze
    REASONS = {
      "NORMATIVE_OR_VALUE" => "This is a value judgment; the system maps its premises but does not assign it a probability.",
      "METAPHYSICAL" => "This is a metaphysical claim; the system does not assign it a probability.",
      "RHETORICAL" => "This is rhetorical rather than a proposition; the system does not assign it a probability.",
      "UNTESTABLE_CURRENT_METHODS" => "This claim is not testable with current methods, as recorded by an auditable contribution.",
      "UNRESOLVED_FORECAST" => "This is a forecast that has not resolved yet.",
      "NO_LEGAL_MODEL" => "This is a legal claim; no legal scoring model exists yet.",
      "NOT_SCORED_BY_MODEL" => "This model does not score claims of this type."
    }.freeze

    module_function

    def for(state) = WORDS.fetch(state, state.to_s.tr("_", " ").capitalize)
    def reason_text(reason) = REASONS.fetch(reason, "Not assessed.")
  end
end
