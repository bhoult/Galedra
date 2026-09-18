# Shared read helpers for the Hotwire pages: snapshot and model selection from
# params, mirroring the API's defaults.
module LedgerView
  extend ActiveSupport::Concern

  included do
    helper_method :current_seq, :selected_model, :released_models
  end

  def head_seq
    Contribution.maximum(:seq) || 0
  end

  def current_seq
    return head_seq if params[:snapshot_seq].blank?

    seq = Integer(params[:snapshot_seq], exception: false)
    seq.nil? || seq.negative? || seq > head_seq ? head_seq : seq
  end

  def selected_model
    return @selected_model if defined?(@selected_model)

    @selected_model = (params[:model].present? && Scoring::Registry.find(params[:model])) || Scoring::Registry.default_model
  rescue Scoring::Registry::Invalid
    @selected_model = Scoring::Registry.default_model
  end

  def released_models
    Scoring::Registry.released.to_a
  end
end
