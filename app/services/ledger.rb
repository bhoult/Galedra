# frozen_string_literal: true

# The contribution log (spec 02). Every epistemic write is a signed contribution
# appended through Ledger::Append; projections are written only by Ledger::Apply.
module Ledger
  PROTOCOL = "eir-contribution-v1"
  ADVISORY_LOCK_KEY = 4_247_101_001 # arbitrary, process-wide constant for the append lock

  class Error < StandardError; end
  class AppendOnlyViolation < Error; end
  class GenesisMismatch < Error; end
  class ChainBroken < Error; end

  # A contribution that failed validation. Nothing is logged; the API renders
  # the errors as 422 in the spec 06 §1 format.
  class Rejected < Error
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(errors.map { |e| "#{e[:code]} at #{e[:path]}: #{e[:detail]}" }.join("; "))
    end
  end

  def self.replaying?
    ActiveSupport::IsolatedExecutionState[:ledger_replaying] == true
  end

  def self.replaying
    previous = ActiveSupport::IsolatedExecutionState[:ledger_replaying]
    ActiveSupport::IsolatedExecutionState[:ledger_replaying] = true
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[:ledger_replaying] = previous
  end

  def self.applying?
    ActiveSupport::IsolatedExecutionState[:ledger_applying] == true
  end

  def self.applying
    previous = ActiveSupport::IsolatedExecutionState[:ledger_applying]
    ActiveSupport::IsolatedExecutionState[:ledger_applying] = true
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[:ledger_applying] = previous
  end
end
