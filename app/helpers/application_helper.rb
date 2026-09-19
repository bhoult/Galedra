module ApplicationHelper
  # The content column of an outline page. Named once, so the page, the tree
  # and every link into it agree. A method rather than a constant, because a
  # view cannot reach a helper's constants by bare name.
  OUTLINE_FRAME = "outline-content"

  def outline_frame = OUTLINE_FRAME

  # A navigation link, with an optional definition of the term it names. Only
  # words that mean something particular here get one: "claim", "audit" and
  # "outline" are not what a reader would assume from ordinary usage, while
  # "users" and "bug reports" are. Explaining the obvious trains people to
  # ignore the explanations.
  #
  # The text is carried as data-tip, which the tooltip controller shows after a
  # second's hover, and as title, which the browser shows when JavaScript is
  # not running. The controller removes the title when it takes over.
  def nav_link(label, path, tip = nil)
    return link_to(label, path) if tip.blank?

    link_to label, path, title: tip, data: { tip: tip }
  end
end
