# Topic pages (Stage 15): the tree with counts, and one page per topic with
# claims and counts by assessment state rolled up from children. Counts only,
# never a score for a topic (06 §6 extended).
class TopicsController < ApplicationController
  allow_unauthenticated_access

  def index
    @seq = current_seq
    @counts = counts_by_topic(@seq)
  end

  def show
    @seq = current_seq
    @node = Topics.find(params[:path])
    raise ActiveRecord::RecordNotFound if @node.nil?

    paths = Topics.paths_under(@node.path)
    ids = ClaimTopic.current_at(@seq).where(topic: paths).select(:claim_id)
    @claims = Claim.counted_at(@seq).where(id: ids).where.not(id: Governance::Quarantines.quarantined_claim_ids).order(created_seq: :desc).limit(100).to_a
    @rows = @claims.map { |c| [ c, selected_model && Scoring::Score.call(c, @seq, selected_model) ] }
    @state_counts = @rows.filter_map { |_, r| r&.assessment_state }.tally.sort_by { |state, _| state }
    @child_counts = @node.children.to_h { |child| [ child, ClaimTopic.current_at(@seq).where(topic: child.path).distinct.count(:claim_id) ] }
  end

  private

  def counts_by_topic(seq)
    direct = ClaimTopic.current_at(seq).group(:topic).distinct.count(:claim_id)
    Topics.tree.to_h do |top|
      rolled = ClaimTopic.current_at(seq).where(topic: Topics.paths_under(top.path)).distinct.count(:claim_id)
      [ top.path, { total: rolled, children: top.children.to_h { |c| [ c.path, direct.fetch(c.path, 0) ] } } ]
    end
  end
end
