# Runs the LLM boundary's deduplication on one affiliation request and applies
# it when the match needs no judgment (EXACT, ALIAS). Idempotent: a request
# already settled is left alone.
class ResolveAffiliationRequestJob < ApplicationJob
  queue_as :default

  def perform(request_id)
    request = AffiliationRequest.find_by(id: request_id)
    return if request.nil? || request.status != "PENDING"

    result = Llm::Adapter.current.resolve_affiliation(request.text)
    request.update!(proposed_slug: result[:slug], confidence: result[:confidence])
    return unless %w[EXACT ALIAS].include?(result[:confidence]) && Affiliations.valid?(result[:slug])

    AffiliationRequest.settle!(normalized: request.normalized, slug: result[:slug], status: "MERGED")
  end
end
