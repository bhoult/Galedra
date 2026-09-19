# Settles reviews that one principal answered and nobody contradicted, once
# the verdict has stood for Reviews::Consensus::ALONE_AFTER. Hourly.
class SettleLoneVerdictsJob < ApplicationJob
  queue_as :default

  def perform
    ContentReview.settle_lone!
    AffiliationRequest.settle_lone!
  end
end
