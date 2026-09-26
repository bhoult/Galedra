# frozen_string_literal: true

module Api
  module V1
    # Outlines (Stage 20): roots, and one section's subtree with counts. Never a
    # probability for a section (06 §6); counts by state with the fixed note.
    class SectionsController < BaseController
      def index
        seq = snapshot_seq
        roots = Sections::Tree.roots(seq).limit(200).map { |r| present(r, Sections::Tree.call(r, seq, model: model, depth: 0), seq) }
        render json: { snapshot_seq: seq, sections: roots, note: Sections::Tree::NOTE }
      end

      def show
        seq = snapshot_seq
        section = Section.find(params[:id])
        raise ActiveRecord::RecordNotFound unless section.counted_at?(seq)

        depth = Integer(params.fetch(:depth, 2), exception: false) || 2
        tree = Sections::Tree.call(section, seq, model: model, depth: depth.clamp(0, Section::MAX_DEPTH))
        render json: { snapshot_seq: seq, path: section.path(seq), section: present(section, tree, seq, children: true), note: Sections::Tree::NOTE }
      end

      private

      def model
        return @model if defined?(@model)

        @model = params[:model].present? ? Scoring::Registry.find(params[:model]) : Scoring::Registry.default_model
      rescue Scoring::Registry::Invalid => e
        raise Ledger::Rejected.new([ { code: "MODEL_UNKNOWN", path: "$.model", detail: e.message } ])
      end

      def present(section, tree, seq, children: false)
        out = { id: section.id, heading: section.heading, root_id: section.root_id, parent_id: section.parent_id, depth: section.depth, position: section.position,
                source_id: section.source_id, location_id: section.location_id, created_seq: section.created_seq, contribution_id: section.contribution_id,
                counts: tree[:counts], pending_claims: tree[:pending], counts_line: Sections::Tree.counts_line(tree[:counts]),
                reading: Sections::Tree.reading(tree) }.compact
        if children
          out[:claims] = tree[:claims].map { |c| { id: c.id, text: c.canonical_text, type: c.claim_type, assessment_state: tree[:states][c.id] } }
          out[:children] = tree[:children].map { |ch| present(ch[:section], ch, seq, children: true) }
        end
        out
      end
    end
  end
end
