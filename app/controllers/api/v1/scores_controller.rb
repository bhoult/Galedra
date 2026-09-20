# frozen_string_literal: true

module Api
  module V1
    # Score-bearing reads (spec 06 §2). Every response carries snapshot_seq,
    # model, and assessment_state; a quarantined claim returns its stub.
    class ScoresController < BaseController
      before_action :load_claim

      def score
        return render json: stub if @quarantine

        result = Scoring::Score.call(@claim, @seq, model)
        render json: { claim_id: @claim.id, snapshot_seq: @seq, model: model.full_name,
                       assessment: Graph::Presenter.assessment(result, @seq, model), trace_hash: result.trace_hash }
      end

      def trace
        return render json: stub if @quarantine

        result = Scoring::Score.call(@claim, @seq, model)
        render json: { claim_id: @claim.id, snapshot_seq: @seq, model: model.full_name, assessment_state: result.assessment_state,
                       trace: result.trace, trace_hash: result.trace_hash, canonical_trace: Scoring::Trace.canonical(result.trace) }
      end

      def compare
        return render json: stub if @quarantine

        names = params[:models].to_s.split(",").map(&:strip).reject(&:empty?)
        # With no models named, compare the pair a reader means: the default and
        # its strict counterpart at the same version. This used to default to
        # every released model and then insist on exactly two, which worked only
        # while exactly two existed — releasing a third turned the bare endpoint
        # into a 422.
        names = default_pair if names.empty?
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.models", detail: "expected models=a,b" } ]) unless names.size == 2

        a, b = names.map { |n| Scoring::Registry.find(n) }
        ra = Scoring::Score.call(@claim, @seq, a)
        rb = Scoring::Score.call(@claim, @seq, b)
        render json: { claim_id: @claim.id, snapshot_seq: @seq, assessment_state: { a.full_name => ra.assessment_state, b.full_name => rb.assessment_state } }
                        .merge(Scoring::Compare.call(ra, rb, config_a: a.config, config_b: b.config))
      end

      # The default model, and the strict model of the same version when there is
      # one, so the comparison stays meaningful as versions accumulate.
      def default_pair
        default = Scoring::Registry.default_model
        strict = ScoringModel.find_by(name: "ledger-strict", semantic_version: default.semantic_version) ||
                 ScoringModel.where(name: "ledger-strict").order(:released_seq).last
        [ default.full_name, strict&.full_name ].compact
      end

      def why
        return render json: stub if @quarantine

        render json: Cards::Why.call(@claim, @seq, model)
      end

      def summary
        return render json: stub if @quarantine

        type = params.fetch(:type, "STANDARD").to_s.upcase
        raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.type", detail: "expected SHORT or STANDARD" } ]) unless Summary::TYPES.include?(type)

        render json: Summaries::Generate.call(@claim, @seq, model, type: type)
      end

      private

      def load_claim
        @seq = snapshot_seq
        @claim = Claim.find(params[:id])
        raise ActiveRecord::RecordNotFound if @claim.created_seq > @seq

        @quarantine = Governance::Quarantines.live_for("CLAIM", @claim.id)
      end

      def model
        @model ||= params[:model].present? ? Scoring::Registry.find(params[:model]) : Scoring::Registry.default_model
      rescue Scoring::Registry::Invalid => e
        raise Ledger::Rejected.new([ { code: "MODEL_UNKNOWN", path: "$.model", detail: e.message } ])
      end

      def stub
        { claim_id: @claim.id, snapshot_seq: @seq, model: nil, assessment_state: "QUARANTINED" }.merge(Governance::Quarantines.stub(@quarantine))
      end
    end
  end
end
