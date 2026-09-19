# Admin → Affiliation requests: what people asked for, grouped by the text
# they asked for, with the deduplicator's proposal; merge, add, or decline.
module Admin
  class AffiliationRequestsController < ApplicationController
    before_action :require_admin

    def index
      pending = AffiliationRequest.pending.order(:created_at).to_a
      @groups = pending.group_by(&:normalized).map do |normalized, rows|
        { normalized: normalized, text: rows.first.text, count: rows.size, proposed_slug: rows.first.proposed_slug, confidence: rows.first.confidence, since: rows.first.created_at }
      end.sort_by { |g| [ -g[:count], g[:since] ] }
      @options = Affiliations.groups.flat_map { |g| g.options.map { |o| [ "#{g.label} / #{o.label}", o.slug ] } }
      @group_choices = Affiliations.curated_groups.map { |g| [ g.label, g.slug ] } + [ [ "Other", "other" ] ]
      @recent = AffiliationRequest.where.not(status: "PENDING").order(resolved_at: :desc).limit(30)
    end

    def merge
      slug = params[:slug].to_s
      return redirect_to admin_affiliation_requests_path, alert: "Pick an existing affiliation." unless Affiliations.valid?(slug)

      AffiliationRequest.settle!(normalized: params[:normalized].to_s, slug: slug, status: "MERGED", by: Current.user)
      redirect_to admin_affiliation_requests_path, notice: "Merged into #{Affiliations.label(slug)} and added to each requester."
    end

    def add
      label = params[:label].to_s.strip
      custom = CustomAffiliation.new(slug: CustomAffiliation.slug_for(label), label: label, group_slug: params[:group_slug].to_s, created_by_id: Current.user.id)
      return redirect_to admin_affiliation_requests_path, alert: custom.errors.full_messages.join("; ") unless custom.save

      AffiliationRequest.settle!(normalized: params[:normalized].to_s, slug: custom.slug, status: "ADDED", by: Current.user)
      redirect_to admin_affiliation_requests_path, notice: "Added #{custom.label} under #{Affiliations.group_of(custom.slug).label} and put it on each requester's account."
    end

    def decline
      AffiliationRequest.decline!(normalized: params[:normalized].to_s, by: Current.user)
      redirect_to admin_affiliation_requests_path, notice: "Declined."
    end
  end
end
