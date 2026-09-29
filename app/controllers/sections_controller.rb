# Outlines (Stage 20, 22): every root ordered by open work or newest, filtered
# by topic; one section's subtree as a directory tree; and a signed-in
# person's "Add an outline" from indented headings.
class SectionsController < ApplicationController
  allow_unauthenticated_access only: [ :index, :show, :contributors ]

  def index
    @seq = current_seq
    roots = Sections::Tree.roots(@seq).includes(:source).limit(200).to_a
    if params[:topic].present?
      claim_ids = ClaimTopic.current_at(@seq).where(topic: Topics.paths_under(params[:topic])).select(:claim_id)
      root_ids = Section.counted_at(@seq).where(id: ClaimPlacement.counted_at(@seq).where(claim_id: claim_ids).select(:section_id)).distinct.pluck(:root_id)
      roots = roots.select { |r| root_ids.include?(r.id) }
    end
    @rows = roots.map { |r| [ r, Sections::Tree.call(r, @seq, model: selected_model), Sections::Progress.call(r, @seq) ] }
    @rows = @rows.sort_by { |_, _, p| [ -p[:open_tasks], -p[:claims] ] } unless params[:sort] == "newest"
    results = @rows.each_with_object({}) { |(_, tree, _), all| Cards::Completeness.tree_results(tree, all) }
    meters = Cards::Completeness.for_results(results, @seq)
    @reviews = @rows.to_h { |root, tree, _| [ root.id, Cards::Completeness.total(Cards::Completeness.tree_results(tree).keys.filter_map { |id| meters[id] }) ] }
  end

  def show
    @seq = current_seq
    @section = Section.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @section.counted_at?(@seq)

    @model = selected_model
    # Two trees, because they answer different questions. @subtree is this
    # section and what is under it, which is what the counts describe. @tree is
    # the whole outline, which is how a reader gets around: building the
    # navigation from the clicked section made its siblings disappear as you
    # went down, and the deeper you went the less there was to go back to.
    @subtree = Sections::Tree.call(@section, @seq, model: @model)
    @tree = @section.parent_id.nil? ? @subtree : Sections::Tree.call(@section.root, @seq, model: @model)
    @ancestors = @section.ancestors(@seq)
    @progress = Sections::Progress.call(@section.root, @seq)
    # A leaf's own text, or a branch's leaves in order (Stage 30).
    @text = Sections::Text.call(@section, @seq)
    @share_line = Sections::Progress.share_line(@section.root, @seq, section_url(@section.root))
    @current_claim = params[:claim].presence
    # How complete the review is, per claim in the tree and for the section
    # being read (owner request, 2026-09-29). One batch for every claim the
    # tree shows, from scores the tree has already computed.
    @meters = Cards::Completeness.for_results(Cards::Completeness.tree_results(@tree), @seq)
    @section_reviews = Cards::Completeness.section_totals(@tree, @meters)
    @review = @section_reviews[@section.id] || Cards::Completeness.total([])
  end

  # The same page for an outline: whoever broke the source into sections counts
  # as much as whoever checked a claim inside it.
  def contributors
    seq = current_seq
    section = Section.find(params[:id])
    # The same guard `show` applies: a section that is not counted at this seq
    # 404s there and must not render its heading and contributor list here.
    raise ActiveRecord::RecordNotFound unless section.counted_at?(seq)

    root = Section.find_by(id: section.root_id) || section
    claim_ids = ClaimPlacement.counted_at(seq).where(section_id: Section.counted_at(seq).where(root_id: root.root_id).select(:id))
                              .distinct.pluck(:claim_id) - Governance::Quarantines.quarantined_claim_ids

    @subject = root.heading
    @back = section_path(root)
    @back_label = "the outline"
    @parties = Attribution::Participants.for_outline(root.root_id, claim_ids)
    render "shared/participants"
  end

  # Indented text → one CREATE_SECTION with a nested payload.
  def create
    source = Source.find(params[:source_id])
    nodes = Sections::Outline.parse(params[:outline].to_s)
    return redirect_to source_path(source), alert: "Give at least one heading." if nodes.empty?

    payload = { "source_id" => source.id, "sections" => nodes }
    payload = { "parent_section_id" => params[:parent_section_id], "sections" => nodes } if params[:parent_section_id].present?
    result = Ui::Write.call(Current.user, "CREATE_SECTION", payload)
    root = Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))
    redirect_to section_path(root.root_id), notice: "Outline recorded as a signed contribution."
  end

  private
end
