# Snapshot view (spec 06 §5): claims as of a seq, with the pinned digest.
class SnapshotsController < ApplicationController
  allow_unauthenticated_access

  def show
    @seq = Integer(params[:seq], exception: false)
    @entry = @seq && Contribution.find_by(seq: @seq)
    raise ActiveRecord::RecordNotFound if @entry.nil?

    @pinned = GraphSnapshot.find_by(seq: @seq)
    @model = selected_model
    @digest = @model && Snapshots::Digest.call(@seq, model: @model)
    listed = Snapshots::Digest.claims_at(@seq).order(:created_seq).limit(100).to_a
    scored = @model ? Scoring::Score.call_many(listed, @seq, @model) : {}
    @claims = listed.map { |c| [ c, scored[c.id] ] }
    @compare_seq = Integer(params[:compare_seq], exception: false)
    if @compare_seq && @model
      then_scored = Scoring::Score.call_many(listed.select { |c| c.created_seq <= @compare_seq }, @compare_seq, @model)
      @compare = listed.to_h { |c| [ c, then_scored[c.id] ] }
    end
  end
end
