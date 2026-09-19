import { Controller } from "@hotwired/stimulus"

// Opening and closing a branch of the outline, with the height animated.
//
// <details> cannot be animated on its own: the browser shows and hides its
// contents instantly, and on closing it removes them before any transition can
// run. So closing is deferred here until the height has finished animating,
// and opening happens first so the content can be measured.
//
// Anyone who has asked for less motion gets none: the branch opens and closes
// the way it always did.
const DURATION = 180

export default class extends Controller {
  connect() {
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.onClick = (event) => this.toggle(event)
    this.element.addEventListener("click", this.onClick)
  }

  disconnect() {
    this.element.removeEventListener("click", this.onClick)
  }

  toggle(event) {
    const link = event.target.closest("a")
    const summary = event.target.closest("summary")

    // A section with something under it is a branch of the menu: its title
    // opens and closes it and fetches nothing. Only a section with no branch
    // left to open, or a claim, loads anything, and then only the content
    // column beside this.
    if (link && !summary) {
      // The outline no longer reloads, so nothing else will move the marker.
      this.markCurrent(link)
      return
    }
    if (link) {
      if (event.defaultPrevented || event.button !== 0) return
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    }
    if (!summary) return

    const details = summary.parentElement
    const reveal = details.querySelector(":scope > .reveal")
    if (!reveal) return

    // The browser toggles a <summary> itself, instantly; take that over so the
    // height can be animated, and so a title click does not do both.
    event.preventDefault()
    if (this.reduced.matches) {
      if (!details.open) this.closeOthers(details)
      details.open = !details.open
      return
    }
    details.open ? this.close(details, reveal) : this.open(details, reveal)
  }

  // Opening one branch closes the others, so the outline stays short enough to
  // take in at a glance. A branch on the path to the one being opened stays
  // open, or opening a child would close its own parent.
  closeOthers(opening) {
    const path = new Set()
    for (let el = opening; el; el = el.parentElement && el.parentElement.closest("details")) path.add(el)

    this.element.querySelectorAll("details[open]").forEach((other) => {
      if (path.has(other)) return

      const reveal = other.querySelector(":scope > .reveal")
      if (!reveal) return

      // One already in flight is left to settle where it was heading.
      reveal.dataset.animating ? (other.open = false) : this.close(other, reveal)
    })
  }

  // Where you are, kept in step with the content beside it.
  markCurrent(link) {
    const row = link.closest("p.leaf, summary, .claim-line") || link
    this.element.querySelectorAll(".current").forEach((el) => el.classList.remove("current"))
    row.classList.add("current")
  }

  open(details, reveal) {
    this.closeOthers(details)
    details.open = true
    this.animate(reveal, 0, reveal.scrollHeight)
  }

  close(details, reveal) {
    const done = () => { details.open = false }
    this.animate(reveal, reveal.scrollHeight, 0, done)
  }

  animate(reveal, from, to, done) {
    if (reveal.dataset.animating) return

    reveal.dataset.animating = "true"
    reveal.style.overflow = "hidden"
    reveal.style.height = `${from}px`
    // Force a reflow so the starting height is the one being transitioned from.
    reveal.offsetHeight // eslint-disable-line no-unused-expressions
    reveal.style.transition = `height ${DURATION}ms ease`
    reveal.style.height = `${to}px`

    const finish = () => {
      reveal.style.transition = ""
      reveal.style.height = ""
      reveal.style.overflow = ""
      delete reveal.dataset.animating
      if (done) done()
    }
    reveal.addEventListener("transitionend", finish, { once: true })
    // A branch with nothing in it never fires transitionend.
    setTimeout(() => { if (reveal.dataset.animating) finish() }, DURATION + 60)
  }
}
