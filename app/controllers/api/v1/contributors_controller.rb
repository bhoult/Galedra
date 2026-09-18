# frozen_string_literal: true

module Api
  module V1
    class ContributorsController < BaseController
      def show
        render json: { contributor: Graph::Presenter.contributor(Contributor.find(params[:id])) }
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
