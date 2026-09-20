# frozen_string_literal: true

# A maintainer's working status for something a person or an assistant filed
# (bug reports and feature requests). Outside the log, mutable, and never an
# input to anything epistemic: marking a report done says the maintainer dealt
# with it, not that the thing reported was true or false.
module Triageable
  extend ActiveSupport::Concern

  STATUSES = %w[OPEN DONE IGNORED].freeze

  included do
    validates :status, inclusion: { in: STATUSES }

    scope :with_status, ->(value) { STATUSES.include?(value.to_s) ? where(status: value.to_s) : all }
    scope :newest_first, -> { order(created_at: :desc) }
  end

  def open? = status == "OPEN"
end
