# Help (Stage 24): the docs page renders the README with pointers to the API,
# the skill, and the spec; the about page says which build is running, which
# node this is, and where the code lives.
class HelpController < ApplicationController
  allow_unauthenticated_access

  README = Rails.root.join("README.md")

  def docs
    # The README uses GitHub fences; kramdown's own parser takes tildes.
    markdown = File.read(README).gsub(/^```(\w*)\s*$/) { "~~~#{$1}" }
    @readme_html = Kramdown::Document.new(markdown, auto_ids: true).to_html.html_safe
  end

  # Every factor in a score, explained, with the numbers taken from the released
  # model rather than written down here. A page that restated the weights in
  # prose would be a second copy of the config, and the second copy is the one
  # that goes stale (owner, 2026-09-22: "I have no idea what those numbers are").
  def scoring
    @models = Scoring::Registry.released.to_a
    @model = (params[:model].present? && Scoring::Registry.find(params[:model])) || Scoring::Registry.default_model
    @config = @model&.config || {}
    @default = Scoring::Registry.default_model
    # One line each. The full comparison for a model is on its own page: at a
    # hundred released models, building every one of those diffs to render a
    # list would be a hundred config comparisons nobody asked for.
    @summaries = @models.to_h { |m| [ m.full_name, Scoring::ModelNotes.summary(m) ] }
  end

  # One released model, on a page of its own: what it is, what its version
  # changed, how it differs from the one beside it, and every number it declares.
  # There may be many of these in time, which is why they are not all one page.
  def model
    @models = Scoring::Registry.released.to_a
    @model = @models.find { |m| m.full_name == params[:name] }
    return redirect_to scoring_path, alert: "No released model by that name." if @model.nil?

    @config = @model.config
    @default = Scoring::Registry.default_model
    @note = Scoring::ModelNotes.for(@model, @models)
  end

  # The OpenAPI description rendered by Swagger UI, the reference renderer. The
  # page holds nothing of its own: it points the renderer at the same JSON every
  # client reads, so it cannot show an API that is not there.
  def api
    @openapi_url = api_v1_openapi_path(format: :json)
    @version = Api::Openapi::VERSION
  end

  def glossary
  end

  # Who to write to, and the routes that beat writing (owner request, 2026-09-19).
  def contact
    @maintainer = Governance::Software::MAINTAINER
    @software = Governance::Software.to_h
    @repository_public = Governance::Software.repository_public?
  end

  # Every licence in the stack in full, and the policy behind it.
  def licenses
    @rows = Governance::Licenses.rows
    @code_license_name = Governance::Licenses.code_license_name
    @code_license_text = Governance::Licenses.code_license_text
    @texts = Governance::Licenses.texts
    @policy_html = Governance::Licenses.policy_html
  end

  # How a person connects their own assistant, in one place. The landing page
  # said "give your assistant one address" and never named the address, and
  # /assistants/new mints a token for somebody who already knows what to do with
  # one. This is the page between those two (Stage 42 §4, and the owner's third
  # path: through the chat as a skill or connector).
  def connect
    @node = Ledger::Node.url
  end

  # The cheapest way in, and the one nobody was told about. Written by Meta's
  # Muse on 2026-09-22 after a long queue run, edited here for two things it
  # could not have known: `introduce_yourself` had just landed, so an agent no
  # longer needs a credential handed to it, and a workflow that reads somebody's
  # social feed has to carry the rule about private individuals.
  def contribute
    @node = Ledger::Node.url
  end

  def about
    @software = Governance::Software.to_h
    @node = Ledger::Node.to_h
    @constitution = Governance::Constitution.new
    @head = Contribution.in_order.last
    @models = Scoring::Registry.released.map(&:full_name)
    @moderator_key_ids = Governance::Moderators.key_ids
    @postgres = ActiveRecord::Base.connection.select_value("SHOW server_version") rescue nil
  end
end
