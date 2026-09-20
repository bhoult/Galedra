# frozen_string_literal: true

# Moderators and admins read what assistants said they could not do (after
# Stage 19). The text is untrusted and is shown nowhere else. The list, the
# detail view and the triage statuses come from Triage (owner request,
# 2026-09-20).
class FeatureRequestsController < ApplicationController
  include Triage

  private

  def triage_model = FeatureRequest
  def triage_index_path = feature_requests_path
end
