# Source pages: the per-source answer card (spec 06 §5), the Analyze-text
# breakdown step (Stage 46: by an assistant or by hand, never proposed by the
# server), claim submission, and verification-task creation.
class SourcesController < ApplicationController
  allow_unauthenticated_access only: [ :show ]

  def show
    @seq = current_seq
    @source = Source.find(params[:id])
    @quarantine = Governance::Quarantines.live_for("SOURCE", @source.id)
    @locations = @source.source_locations.active_at(@seq).order(:created_seq)
    @cards = selected_model && !@quarantine ? Cards::SourceCard.call(@source, @seq, selected_model) : nil
    @tasks = Task.where(target_type: "CLAIM", target_id: @cards ? @cards[:cards].map { |c| c[:claim_id] } : []).order(:created_at)
    # The completeness gauge beside each card's score (owner, 2026-09-29); the
    # scores are cached, so this is one batch.
    claims = @cards ? Claim.where(id: @cards[:cards].map { |c| c[:claim_id] }).to_a : []
    @meters = claims.any? ? Cards::Completeness.for_results(Scoring::Score.call_many(claims, @seq, selected_model), @seq) : {}
  end

  # The breakdown, offered two ways: a prompt for the person's own assistant,
  # and an empty form. The extraction tasks the paste opened are listed too.
  def analyze
    @source = Source.find(params[:id])
    @rows = rows_with_blanks([])
    prepare_breakdown
  end

  # Each claim typed on the form becomes the user's own CREATE_CLAIM. "Check
  # wording" shows Claims::Atomicity's warnings beside each row and records
  # nothing; a row without the private-individual affirmation stops the whole
  # form before anything is written, and the writes are one transaction, so a
  # half-recorded form cannot happen.
  def create_claims
    @source = Source.find(params[:id])
    rows = submitted_rows
    if params[:check].present? || rows.empty?
      @rows = rows_with_blanks(rows)
      @error = "Type at least one claim." if rows.empty? && params[:check].blank?
      prepare_breakdown
      return render :analyze, status: (@error ? :unprocessable_content : :ok)
    end
    if rows.any? { |r| !r["affirms"] }
      @rows = rows_with_blanks(rows)
      @error = "PRIVATE_INDIVIDUAL_AFFIRMATION_REQUIRED: affirm that each claim is not about an identifiable private individual. Nothing was recorded."
      prepare_breakdown
      return render :analyze, status: :unprocessable_content
    end

    # One transaction, as Investigations::Record does: a refusal on any row
    # (a claim too long, a topic not in the vocabulary) appends none of them.
    Contribution.transaction do
      rows.each do |row|
        payload = { "canonical_text" => row["canonical_text"], "claim_type" => row["claim_type"],
                    "affirms_not_private_individual" => true, "source_id" => @source.id }
        result = Ui::Write.call(Current.user, "CREATE_CLAIM", payload)
        topics = row["topics"].first(Topics::MAX_PER_CLAIM)
        Ui::Write.call(Current.user, "TAG_CLAIM", { "claim_id" => Ledger::Ids.derive(result.contribution.id, "claim"), "topics" => topics }) if topics.any?
      end
    end
    Sources::Paste.cancel_extraction!(@source, Ui::Write.contributor_for(Current.user)&.id)
    redirect_to source_path(@source), notice: "#{rows.size} claim#{'s' unless rows.size == 1} recorded as signed contributions."
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

  private

  BLANK_ROWS = 5

  def submitted_rows
    params.fetch(:claims, {}).each_value.filter_map do |entry|
      attrs = entry.permit(:canonical_text, :claim_type, :affirms_not_private_individual, topics: [])
      text = attrs["canonical_text"].to_s.strip
      next if text.empty?

      { "canonical_text" => text, "claim_type" => attrs["claim_type"].presence_in(Claim::TYPES) || "OBSERVATIONAL",
        "affirms" => attrs["affirms_not_private_individual"] == "1", "topics" => Array(attrs["topics"]).reject(&:blank?),
        "warnings" => Claims::Atomicity.warnings(text) }
    end
  end

  def rows_with_blanks(rows)
    blank = { "canonical_text" => "", "claim_type" => "OBSERVATIONAL", "affirms" => false, "topics" => [], "warnings" => [] }
    rows + Array.new([ BLANK_ROWS - rows.size, 2 ].max) { blank.dup }
  end

  def prepare_breakdown
    @tasks = Task.where(task_type: "CLAIM_EXTRACTION", target_type: "SOURCE", target_id: @source.id).order(:created_at).to_a
    @recorded = Cards::SourceCard.extracted_claims(@source, head_seq).count
    @prompt = "galedra: Break the text below into its atomic claims, search Galedra for each, and record them as one check with " \
              "record_investigation, giving each new claim source: \"#{@source.id}\" so it is filed under the text I pasted at " \
              "#{source_url(@source)}. Then give me the share line.\n\n#{@source.content}"
  end
end
