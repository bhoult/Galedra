# frozen_string_literal: true

# Everything a conversation here has in common: turns, clipping, and a way to
# say whose move it is (Stage 37).
#
# There is one of these because two implementations of a conversation drift, and
# the drift is not hypothetical. On 2026-09-20 a guidance line and a refusal hint
# said different things about when to file a report, and the narrower one won
# because it was the one being read at the moment of deciding. A bug report, a
# feature request and a thread on a determination are the same object with
# different rules about who closes it, so the rules are the only thing that
# differs.
#
# **Settlement is the one seam.** A model declares `settles_by`, and that object
# answers what the status becomes, what the state reads as, and whether the
# thing is held. Nothing else in here knows which rule it is under, which is the
# property that stops a second branch growing in this file later.
module Threadable
  extend ActiveSupport::Concern

  included do
    has_many :turns, class_name: "ThreadTurn", as: :thread, dependent: :destroy, inverse_of: :thread
    # The register named them messages first, and its views and specs still do.
    # One association, two names, rather than two associations.
    alias_method :messages, :turns
  end

  # Records one turn and says whether it had to be clipped. Clipped, never
  # refused: a caller told its prose was too long by an exception has lost the
  # prose, which cost an assistant half an answer before this was true.
  def add_turn!(body:, author_kind:, token: nil, user: nil, **attrs)
    text = body.to_s.strip
    turns.create!(author_kind: author_kind, assistant_token: token, user: user,
                  body: text[0, ThreadTurn::MAX_CHARS], created_at: Time.current, **attrs)
    text.length > ThreadTurn::MAX_CHARS
  end

  # Whose move it is, in three widths: a key for styling, a mark and one word for
  # a narrow column, and the sentence for a tooltip and the page. The list column
  # is a few characters wide and the full sentence wrapped to four lines in it.
  def state_badge = settlement.badge(self)
  def state_line = state_badge.last
  def held? = settlement.held?(self)
  def settles_at = settlement.settles_at(self)
  def settlement = self.class.settlement

  class_methods do
    def settles_by(object) = @settlement = object

    def settlement = @settlement || superclass.try(:settlement)
  end
end
