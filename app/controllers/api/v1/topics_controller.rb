# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/topics (Stage 15): the vocabulary with claim counts.
    class TopicsController < BaseController
      def index
        seq = snapshot_seq
        direct = ClaimTopic.current_at(seq).group(:topic).distinct.count(:claim_id)
        render json: { snapshot_seq: seq, topics: Topics.tree.map { |t|
          { path: t.path, label: t.label, scope: t.scope, domain: t.domain, claims: ClaimTopic.current_at(seq).where(topic: Topics.paths_under(t.path)).distinct.count(:claim_id),
            children: t.children.map { |c| { path: c.path, label: c.label, domain: c.domain, claims: direct.fetch(c.path, 0) } } }
        } }
      end
    end
  end
end
