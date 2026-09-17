# frozen_string_literal: true

module Ledger
  module Appliers
    # CREATE_INDEPENDENCE_GROUP (spec 02 §3.3).
    module CreateIndependenceGroup
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        enum!(p, "group_type", IndependenceGroup::TYPES)
        string_or_nil!(p, "description")
      end

      def self.apply(c)
        p = c.payload
        IndependenceGroup.create!(
          id: Ids.derive(c.id, "group"), contribution_id: c.id, created_seq: c.seq,
          group_type: p["group_type"], description: p["description"]
        )
      end
    end
  end
end
