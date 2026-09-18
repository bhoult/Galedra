# Source pages: the per-source answer card (spec 06 §5), the Analyze-text
# proposal step, claim submission, and verification-task creation.
class SourcesController < ApplicationController
  allow_unauthenticated_access only: [ :show ]

  def show
    @seq = current_seq
    @source = Source.find(params[:id])
    @quarantine = Governance::Quarantines.live_for("SOURCE", @source.id)
    @locations = @source.source_locations.active_at(@seq).order(:created_seq)
    @cards = selected_model && !@quarantine ? Cards::SourceCard.call(@source, @seq, selected_model) : nil
    @tasks = Task.where(target_type: "CLAIM", target_id: @cards ? @cards[:cards].map { |c| c[:claim_id] } : []).order(:created_at)
  end

  def analyze
    @source = Source.find(params[:id])
    @proposals = Llm::Adapter.current.extract_claims(@source.content.to_s)
  end

  # Each selected proposal becomes the user's own CREATE_CLAIM (accepted after validation).
  def create_claims
    source = Source.find(params[:id])
    created = 0
    params.fetch(:claims, {}).each_value do |entry|
      attrs = entry.permit(:include, :canonical_text, :claim_type, :affirms_not_private_individual, topics: [])
      next unless attrs["include"] == "1"

      payload = { "canonical_text" => attrs["canonical_text"].to_s.strip, "claim_type" => attrs["claim_type"],
                  "affirms_not_private_individual" => attrs["affirms_not_private_individual"] == "1", "source_id" => source.id }
      result = Ui::Write.call(Current.user, "CREATE_CLAIM", payload)
      topics = Array(attrs["topics"]).reject(&:blank?).first(Topics::MAX_PER_CLAIM)
      Ui::Write.call(Current.user, "TAG_CLAIM", { "claim_id" => Ledger::Ids.derive(result.contribution.id, "claim"), "topics" => topics }) if topics.any?
      created += 1
    end
    redirect_to source_path(source), notice: "#{created} claim#{'s' unless created == 1} recorded as signed contributions."
  end

  # "Create verification tasks": opposing search and qualifier check for each
  # extracted claim, plus verification against the pasted text itself.
  def create_tasks
    source = Source.find(params[:id])
    location = source.source_locations.live.order(:created_seq).first
    claims = Cards::SourceCard.extracted_claims(source, head_seq)
    count = 0
    claims.each do |claim|
      %w[OPPOSING_EVIDENCE_SEARCH QUALIFIER_CHECK].each do |type|
        next if Task.exists?(task_type: type, target_type: "CLAIM", target_id: claim.id)

        Tasks::Create.call(task_type: type, target: claim, created_by: Ui::Write.contributor_for(Current.user))
        count += 1
      end
      next if location.nil? || Task.exists?(task_type: "EVIDENCE_VERIFICATION", target_type: "CLAIM", target_id: claim.id)

      Tasks::Create.call(task_type: "EVIDENCE_VERIFICATION", target: claim, location: location, created_by: Ui::Write.contributor_for(Current.user))
      count += 1
    end
    redirect_to source_path(source), notice: "#{count} task#{'s' unless count == 1} created."
  end
end
