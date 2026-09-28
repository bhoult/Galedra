# frozen_string_literal: true

module Assistants
  # Rails fixes a rate limiter's store when the controller class loads. This
  # delegator reads Rails.cache at call time, so a test can swap in a memory
  # store and exercise the limit.
  module RateLimitStore
    module_function

    def increment(...) = Rails.cache.increment(...)
    def read(...) = Rails.cache.read(...)
    def write(...) = Rails.cache.write(...)
  end

  # retry_after_seconds, when the cap is one that lifts on its own. A worker at
  # the hourly write cap was told only that it "resumes as the last hour rolls
  # past", and filed twice for the number (01a0e9d4-9115, 01a0e9d4-9ade).
  class CapReached < StandardError
    attr_reader :retry_after_seconds

    def initialize(message = nil, retry_after_seconds: nil)
      super(message)
      @retry_after_seconds = retry_after_seconds
    end

    def to_error = { code: "DAILY_CAP", path: "$", detail: message, retry_after_seconds: retry_after_seconds }.compact
  end
end
