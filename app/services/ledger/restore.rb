# frozen_string_literal: true

module Ledger
  # Restores a contribution whose invalidation a re-audit overturned (spec 05
  # §9 appeals): its projection rows come back as new rows with a new
  # created_seq, so history shows the gap. Ids derive from the restoring ACCEPT.
  module Restore
    SKIP = %w[id created_seq invalidated_seq accepted_seq].freeze

    module_function

    def copy_rows(original, accept_contribution)
      original.projection_rows.select(&:invalidated?).each_with_index do |row, index|
        attributes = row.attributes.except(*SKIP)
        row.class.create!(attributes.merge("id" => Ids.derive(accept_contribution.id, row.class.table_name, index),
                                           "created_seq" => accept_contribution.seq,
                                           **(row.has_attribute?(:accepted_seq) ? { "accepted_seq" => accept_contribution.seq } : {})))
      end
    end
  end
end
