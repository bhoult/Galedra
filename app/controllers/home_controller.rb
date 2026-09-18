class HomeController < ApplicationController
  allow_unauthenticated_access

  # Claims of the public demo (08 §7), looked up by wording so the landing page
  # can link its worked example to the live graph when the demo is seeded.
  DEMO_CLAIMS = {
    "C2" => "62% of remote workers report higher productivity",
    "C4" => "Journal of Distributed Work Research"
  }.freeze

  def index
    @constitution = Governance::Constitution.new
    @head = Contribution.in_order.last
    @claim_count = Claim.counted_at(head_seq).count
    if authenticated?
      @recent_audits = Audit.order(created_seq: :desc).limit(5)
      render :dashboard
    else
      @demo_links = demo_links
      render :landing
    end
  end

  def constitution
    @constitution = Governance::Constitution.new
  end

  def faq
  end

  private

  def demo_links
    DEMO_CLAIMS.transform_values { |fragment| Claim.counted_at(head_seq).where("canonical_text LIKE ?", "%#{Claim.sanitize_sql_like(fragment)}%").order(:created_seq).first }.compact
  end
end
