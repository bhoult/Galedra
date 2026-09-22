# frozen_string_literal: true

module Assistants
  # An assistant naming itself and taking a credential of its own.
  #
  # The credential grants nothing that a caller without one did not already
  # have: the principal is anonymous, so the task queue still refuses it and
  # adoption by a signed-in person is still the only way through. What it
  # changes is that the caller stops being keyed by the address it happens to
  # arrive from (Assistants::Connect.for_source), which is what an assistant
  # running in someone's cloud cannot keep.
  module Introduce
    PER_SOURCE_PER_DAY = 5

    module_function

    # Bounded, because a mint costs three signed entries in a log that cannot
    # forget them. Keyed on the address rather than on the caller's token, or
    # the limit would be defeated by the very rotation it is here to serve — a
    # caller that rotates addresses is the case this exists for, so the bound is
    # generous rather than tight, and it stops a loop rather than a determined
    # abuser. Rate limiting the endpoint is McpController's job.
    def call(name:, provider:, model: nil, token: nil, address: nil)
      key = source_key(token, address)
      if key && AssistantToken.where(mint_source_key: key).where(created_at: Time.current.all_day).count >= PER_SOURCE_PER_DAY
        raise CapReached, "this address has taken #{PER_SOURCE_PER_DAY} assistant tokens today; keep the one you were given " \
                       "and send it as Authorization: Bearer, or ask the person to adopt it"
      end

      record, secret = Connect.call(name: name, provider: provider, model: model)
      record.update!(mint_source_key: key) if key
      [ record, secret ]
    end

    # The anonymous token a caller already holds is keyed by address and date, so
    # it is the address we can see without storing one — this node deliberately
    # keeps no client IPs, and that does not change here.
    def source_key(token, address)
      return token.source_key if token.respond_to?(:source_key) && token.source_key.present?
      return nil if address.blank?

      Digest::SHA256.hexdigest("#{address}|#{Date.current}")
    end
  end
end
