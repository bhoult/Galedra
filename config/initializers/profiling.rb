# frozen_string_literal: true

# Per-request profiling (Stage 26), off unless LEDGER_PROFILE is set.
#
# The gem is in the development bundle group and the production image installs
# with BUNDLE_WITHOUT=development, so this file finds nothing to require there;
# the guard on Rails.env is a second lock on the same door. Nothing is loaded
# and no middleware is inserted unless the flag is on, so an ordinary
# development boot carries none of it.
if Rails.env.development? && ENV["LEDGER_PROFILE"].present?
  require "rack-mini-profiler"

  Rack::MiniProfiler.config.position = "bottom-right"
  Rack::MiniProfiler.config.start_hidden = true
  # Its own storage, in memory, so profiling never writes to the ledger's
  # database or its cache.
  Rack::MiniProfiler.config.storage = Rack::MiniProfiler::MemoryStore
  # Profiling is a local tool, not a public one: it must never answer a request
  # that is not from this machine.
  Rack::MiniProfiler.config.authorization_mode = :allow_authorized

  Rails.application.config.after_initialize do
    Rails.logger.info "rack-mini-profiler on: append ?pp=help to a URL for the options"
  end
end
