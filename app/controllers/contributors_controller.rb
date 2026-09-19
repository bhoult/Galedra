# Contributor pages (spec 06 §5) and, on the owner's request of 2026-09-19,
# the contributors list: the hundred principals with the most work done.
class ContributorsController < ApplicationController
  allow_unauthenticated_access

  def index
    @since = ClaimReference.since_for(params[:window])
    @rows = Contributors::Tally.top(limit: 100, since: @since)
  end

  def show
    @seq = current_seq
    @contributor = Contributor.find(params[:id])
    @buckets = Reputation::Calculate.buckets(contributor_id: @contributor.id, snapshot_seq: @seq)
    @tally = Contributors::Tally.for(@contributor.id)
    @recent = @contributor.contributions.in_order.last(20).reverse
    @delegations = @contributor.delegations_as_principal.to_a + @contributor.delegations_as_delegate.to_a
  end
end
