module ApplicationHelper
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
