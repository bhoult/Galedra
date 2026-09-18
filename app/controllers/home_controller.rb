class HomeController < ApplicationController
  allow_unauthenticated_access

  def index
    @constitution = Governance::Constitution.new
    @head = Contribution.in_order.last
    @recent_audits = Audit.order(created_seq: :desc).limit(5)
    @claim_count = Claim.counted_at(head_seq).count
  end
end
