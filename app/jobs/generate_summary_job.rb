# Pre-generates a summary (spec 04 §10); reads generate on demand anyway.
class GenerateSummaryJob < ApplicationJob
  queue_as :default

  def perform(claim_id, seq, model_name, type = "STANDARD")
    Summaries::Generate.call(Claim.find(claim_id), seq, Scoring::Registry.find(model_name), type: type)
  end
end
