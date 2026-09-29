# frozen_string_literal: true

# Full-text indexes for the site search (2026-09-29): an outline's section
# headings, the passages its sections read and quote (and every other quoted
# passage), and investigation statements. Claims already carry one
# (index_claims_on_canonical_text_fts). The expressions match the queries'
# exactly, which is what lets Postgres use them.
class IndexTextForSearch < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :source_locations, "to_tsvector('english', excerpt)", using: :gin, algorithm: :concurrently, name: "index_source_locations_on_excerpt_fts"
    add_index :sections, "to_tsvector('english', heading)", using: :gin, algorithm: :concurrently, name: "index_sections_on_heading_fts"
    add_index :investigations, "to_tsvector('english', statement)", using: :gin, algorithm: :concurrently, name: "index_investigations_on_statement_fts"
  end
end
