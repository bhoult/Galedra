module ApplicationHelper
  # A navigation link that explains itself. The description is carried as
  # data-tip, which the tooltip controller shows after a second's hover, and as
  # title, which the browser shows when JavaScript is not running. The
  # controller removes the title when it takes over, so nobody sees two.
  def nav_link(label, path, tip)
    link_to label, path, title: tip, data: { tip: tip }
  end
end
