# A pinned (seq, entry_hash), optionally labelled (spec 02 §3.5).
class GraphSnapshot < ApplicationRecord
  validates :seq, presence: true, uniqueness: true
  validates :entry_hash, presence: true
end
