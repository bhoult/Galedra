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
    # Generated from the document clients read, so the table cannot drift.
    @api_reference = Api::Openapi.reference
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
