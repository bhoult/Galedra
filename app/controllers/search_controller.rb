# frozen_string_literal: true

# Search the text an investigation or outline holds (owner request,
# 2026-09-29): section headings and readings, statements, claims, and quoted
# passages. Search::Text holds the rules; this page shows the four groups.
class SearchController < ApplicationController
  allow_unauthenticated_access
  # Open to anyone, so bounded per address, and each group is capped: nobody
  # unauthenticated makes the node do unbounded work (Stage 43).
  rate_limit to: 30, within: 1.minute, by: -> { request.remote_ip }, only: :index,
             with: -> { render plain: "Too many searches from this address. Wait a minute and try again.", status: :too_many_requests }

  def index
    @query = params[:q].to_s.squish
    @too_long = @query.length > Search::Text::MAX_QUERY_CHARS
    @result = Search::Text.call(@too_long ? "" : @query, current_seq)
  end
end
