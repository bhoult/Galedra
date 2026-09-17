# ASSIGN_INDEPENDENCE_GROUP as a windowed row so it can be audited and
# invalidated on its own (spec 02 §3.3). evidence_items.independence_group_id
# caches the latest counted assignment.
class IndependenceGroupAssignment < ApplicationRecord
  include GraphProjection

  belongs_to :evidence_item
  belongs_to :independence_group
end
