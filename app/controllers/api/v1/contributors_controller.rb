# frozen_string_literal: true

module Api
  module V1
    class ContributorsController < BaseController
      def show
        contributor = Contributor.find(params[:id])
        render json: { contributor: Graph::Presenter.contributor(contributor).merge(work: Contributors::Tally.for(contributor.id)) }
      end

      # GET /api/v1/contributors/top?window=30d|365d: the hundred principals
      # with the most work done. Volume, never reliability or a score input.
      def top
        rows = Contributors::Tally.top(limit: 100, since: ClaimReference.since_for(params[:window]))
        render json: { note: Contributors::Tally::NOTE, contributors: rows.map { |c, n| { id: c.id, key_id: c.key_id, display_name: c.display_name, identity_tier: c.identity_tier, work: n } } }
      end

      # GET /api/v1/contributors/:id/reputation?snapshot_seq= (spec 05 §6–§7):
      # audited task reliability per task type and domain, never a global score.
      def reputation
        seq = snapshot_seq
        contributor = Contributor.find(params[:id])
        render json: { contributor_id: contributor.id, key_id: contributor.key_id, snapshot_seq: seq,
                       buckets: Reputation::Calculate.buckets(contributor_id: contributor.id, snapshot_seq: seq),
                       note: "Reputation measures audited reliability at a task in a domain. It is not authority and is not a scoring input in v0.1." }
      end
    end
  end
end
