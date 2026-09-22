# Shared read helpers for the Hotwire pages: snapshot and model selection from
# params, mirroring the API's defaults.
module LedgerView
  extend ActiveSupport::Concern

  included do
    helper_method :current_seq, :selected_model, :released_models, :preferred_model_name
  end

  def head_seq
    Contribution.maximum(:seq) || 0
  end

  def current_seq
    return head_seq if params[:snapshot_seq].blank?

    seq = Integer(params[:snapshot_seq], exception: false)
    seq.nil? || seq.negative? || seq > head_seq ? head_seq : seq
  end

  # In order: what this link asked for, what this reader chose, what the node
  # serves by default. A `?model=` on the link always wins, so a shared link
  # shows the same answer to whoever opens it — a preference that silently
  # rewrote somebody else's link would make two readers of one URL see two
  # different numbers with nothing saying why.
  def selected_model
    return @selected_model if defined?(@selected_model)

    @selected_model = model_from(params[:model]) || model_from(preferred_model_name) || Scoring::Registry.default_model
  end

  def preferred_model_name
    Current.user&.preferred_model.presence || session[:preferred_model].presence
  end

  def model_from(name)
    return nil if name.blank?

    Scoring::Registry.find(name)
  rescue Scoring::Registry::Invalid, ActiveRecord::RecordNotFound
    nil
  end

  # Memoised per request: the header picker asks for these on every page, and
  # the page's own selector asks again.
  def released_models
    @released_models ||= Scoring::Registry.released.to_a
  end
end
