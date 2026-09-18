class ContributorsController < ApplicationController
  allow_unauthenticated_access

  def show
    @seq = current_seq
    @contributor = Contributor.find(params[:id])
    @buckets = Reputation::Calculate.buckets(contributor_id: @contributor.id, snapshot_seq: @seq)
    @recent = @contributor.contributions.in_order.last(20).reverse
    @delegations = @contributor.delegations_as_principal.to_a + @contributor.delegations_as_delegate.to_a
  end
end
