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
