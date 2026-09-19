# frozen_string_literal: true

module Bench
  # Holds development's conveniences still for the length of a measurement.
  #
  # The reloader stats the source tree on every request, verbose query logs
  # walk the caller for every query, and the log is written to disk. In a first
  # profile of the weaknesses page those three were a fifth of the samples.
  # None of them exists in production, so a benchmark that includes them is
  # measuring the wrong program. Everything is restored afterwards.
  module Isolation
    module_function

    # cold: swap Rails.cache for a null store, so a page that caches its own
    # answer is measured doing the work rather than reading yesterday's. The
    # score cache is a table, not this, so Scoring::Score keeps its cached and
    # cold readings either way.
    def call(cold: false)
      reloader = Rails.application.reloader
      cache = Rails.cache
      check = reloader.respond_to?(:check) ? reloader.check : nil
      verbose = ActiveRecord.verbose_query_logs if ActiveRecord.respond_to?(:verbose_query_logs)
      level = Rails.logger&.level

      reloader.check = -> { false } if check
      ActiveRecord.verbose_query_logs = false if ActiveRecord.respond_to?(:verbose_query_logs=)
      Rails.logger.level = Logger::ERROR if Rails.logger
      Rails.cache = ActiveSupport::Cache::NullStore.new if cold

      yield
    ensure
      reloader.check = check if check
      ActiveRecord.verbose_query_logs = verbose if ActiveRecord.respond_to?(:verbose_query_logs=) && !verbose.nil?
      Rails.logger.level = level if Rails.logger && level
      Rails.cache = cache if cold
    end

    # What was held still, for the footer of a report, so a number is never
    # read without knowing how it was taken.
    def note(cold: false)
      "measured with the reloader, verbose query logs and log writes held still#{', and no page cache' if cold}; " \
        "#{Rails.env} on #{Etc.uname[:sysname]}, #{Etc.nprocessors} cpu"
    end
  end
end
