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

  class CapReached < StandardError; end
end
