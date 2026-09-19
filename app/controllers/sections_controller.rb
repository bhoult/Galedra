# Outlines (Stage 20): every root, one section's subtree as a directory tree,
# and a signed-in person's "Add an outline" from indented headings.
class SectionsController < ApplicationController
  allow_unauthenticated_access only: [ :index, :show ]

  def index
    @seq = current_seq
    @roots = Sections::Tree.roots(@seq).includes(:source).limit(200).map { |r| [ r, Sections::Tree.call(r, @seq, model: selected_model) ] }
  end

  def show
    @seq = current_seq
    @section = Section.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @section.counted_at?(@seq)

    @model = selected_model
    @tree = Sections::Tree.call(@section, @seq, model: @model)
    @ancestors = @section.ancestors(@seq)
    @current_claim = params[:claim].presence
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
end
