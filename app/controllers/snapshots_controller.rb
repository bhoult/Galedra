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
    @claims = Snapshots::Digest.claims_at(@seq).order(:created_seq).limit(100).map { |c| [ c, @model && Scoring::Score.call(c, @seq, @model) ] }
    @compare_seq = Integer(params[:compare_seq], exception: false)
    @compare = @compare_seq && @model && @claims.map { |c, _| [ c, c.created_seq <= @compare_seq ? Scoring::Score.call(c, @compare_seq, @model) : nil ] }.to_h
  end
end
