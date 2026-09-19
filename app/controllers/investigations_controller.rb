# The paste flow (IMPLEMENTATION.md, after Stage 14): an assistant that cannot
# call tools drafts the investigation bundle; the person pastes it here and
# Galedra records it. No account is needed. The browser session gets one
# connected-assistant token, minted on first use, so the writes are signed,
# delegated, capped, and attributed like any other assistant's.
class InvestigationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 20, within: 1.minute, only: :create, with: -> { redirect_to new_investigation_path, alert: "Too many submissions. Wait a minute and try again." }

  def new
    @bundle_text = params[:bundle].presence || example_bundle
  end

  def create
    bundle = JSON.parse(params[:bundle].to_s)
    bundle["on_duplicate"] = "create" if params[:on_duplicate] == "create"
    apply_attachments!(bundle)
    @bundle_text = JSON.pretty_generate(bundle)
    @result = Investigations::Record.call(session_token, bundle, base_url: request.base_url)
    render @result[:recorded] ? :recorded : :duplicates
  rescue JSON::ParserError => e
    @bundle_text = params[:bundle].to_s
    @errors = [ { code: "SCHEMA_INVALID", path: "$", detail: "That is not valid JSON: #{e.message}" } ]
    render :new, status: :unprocessable_content
  rescue Ledger::Rejected => e
    @bundle_text = params[:bundle].to_s
    @errors = e.errors
    render :new, status: :unprocessable_content
  rescue Assistants::CapReached => e
    redirect_to new_investigation_path, alert: e.message
  end

  # The shareable page for one check (after Stage 19): what was asked, and the answers.
  def show
    @investigation = Investigation.find(params[:id])
    @seq = Contribution.maximum(:seq)
    @model = Scoring::Registry.default_model
    @claims = @investigation.claims.reject { |c| Governance::Quarantines.live_for("CLAIM", c.id) }
    @results = @claims.to_h { |c| [ c.id, Scoring::Score.call(c, @seq, @model) ] }
    @cards = @claims.to_h { |c| [ c.id, Cards::ClaimCard.call(c, @seq, @model, @results[c.id]) ] }
    @headlines = @cards.values.map { |k| k[:plain][:headline] }
    @verdict = Investigations::Verdict.call(@claims, @seq, @model)
    @summary = Investigation.summary(@cards.values, @verdict)
    @share_line = Investigation.share_line(url: investigation_url(@investigation), **@summary.except(:badge))
    @sources = @claims.flat_map { |c| c.evidence_claim_links.effective_at(@seq).includes(evidence_item: { source_location: :source }).map { |l| l.evidence_item.source_location.source } }
                      .uniq.reject(&:redacted?)
  end

  def card
    investigation = Investigation.find(params[:id])
    send_data Cards::StatementImage.render(investigation, base_url: request.host), type: "image/png", disposition: "inline"
  end

  private

  # attach[handle]=claim_id from the duplicates page: the assistant's claim
  # becomes a reference to the existing one and its evidence attaches there.
  def apply_attachments!(bundle)
    attachments = params.fetch(:attach, {}).to_unsafe_h.select { |_, id| id.present? }
    return if attachments.empty?

    bundle["claims"] = Array(bundle["claims"]).map do |claim|
      id = attachments[claim["handle"]]
      id ? { "handle" => claim["handle"], "attach_to" => id } : claim
    end
  end

  def session_token
    token = AssistantToken.find_by_token(session[:paste_token]) if session[:paste_token]
    return token if token&.usable?

    name = authenticated? ? "Pasted by #{Current.user.email_address.split('@').first}" : "Pasted by hand"
    record, plaintext = Assistants::Connect.call(user: authenticated? ? Current.user : nil, name: name, provider: "other", model: "pasted")
    session[:paste_token] = plaintext
    record
  end

  def example_bundle
    bundle = JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about")
    bundle["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    JSON.pretty_generate(bundle)
  end
end
