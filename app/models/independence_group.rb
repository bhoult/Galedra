# Evidence sharing an upstream origin (spec 02 §3.3).
class IndependenceGroup < ApplicationRecord
  include GraphProjection

  TYPES = %w[SAME_PRIMARY_TEXT SAME_PRESS_RELEASE SAME_DATASET SAME_EXPERIMENT SAME_WITNESS_CHAIN SAME_PAPER_FAMILY OTHER].freeze

  has_many :assignments, class_name: "IndependenceGroupAssignment", dependent: nil

  validates :group_type, inclusion: { in: TYPES }
end
