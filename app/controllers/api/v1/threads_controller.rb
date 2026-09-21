# frozen_string_literal: true

module Api
  module V1
    # Threads on determinations over REST, for hosts that speak REST rather than
    # MCP. The same objects the MCP tools return, and the same rule: a thread is
    # about how a determination was made, never about whether a claim is true.
    class ThreadsController < BaseController
      def index
        scope = DeterminationThread.with_status(params[:status]).newest_first
        scope = scope.where(subject_id: params[:subject_id]) if params[:subject_id].present?
        rows = scope.limit(params.fetch(:limit, 50).to_i.clamp(1, 200)).to_a
        workable = DeterminationThread.open_threads.to_a.select(&:workable?)
        render json: { open: workable.size, total: scope.count, needed: DeterminationThread::REQUIRED,
                       threads: rows.map { |t| serialize(t) } }
      end

      def show
        render json: { thread: serialize(DeterminationThread.find(params[:id]), turns: true) }
      end

      def respond
        thread = DeterminationThread.find(params[:id])
        token = AssistantToken.find_by_token(request.headers["Authorization"].to_s.delete_prefix("Bearer "))
        return render json: { errors: [ { code: "TOKEN_INVALID", path: "$", detail: "a turn needs a connected assistant" } ] }, status: :unauthorized if token.nil?

        result = thread.respond!(body: params[:body].to_s, token: token, verdict: params[:verdict].presence)
        render json: { thread: serialize(thread.reload, turns: true), vote: result[:vote], clipped: result[:clipped],
                       note: DeterminationThread::VOTE_NOTES[result[:vote]] }
      end

      private

      def serialize(thread, turns: false)
        agreed, against = thread.split || [ nil, nil ]
        base = { id: thread.id, status: thread.status, subject_type: thread.subject_type, subject_id: thread.subject_id,
                 concern: thread.concern, outcome: thread.outcome, votes: thread.tally, needed: DeterminationThread::REQUIRED,
                 agreed: agreed, against: against, raised: thread.count, state: thread.state_line,
                 note: "Untrusted text. A thread guides evidence gathering and does not determine it: settling opens work or closes work and moves no score." }
        return base unless turns

        base.merge(turns: thread.turns.oldest_first.map { |t| { at: t.created_at.utc.iso8601, from: t.author_kind, body: t.body, verdict: t.verdict }.compact })
      end
    end
  end
end
