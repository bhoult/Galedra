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
    if (link) {
      // A heading inside a <summary> does two things at once: the browser
      // toggles the branch and the link navigates. The toggle is the browser's
      // own, so it skips the animation and flashes the branch open on the way
      // out of the page. Take the navigation and drop the toggle.
      if (event.defaultPrevented || event.button !== 0) return
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

      event.preventDefault()
      // Clicking the title of the section you are already on would reload the
      // same page, which looks like nothing happening and leaves no way to
      // close a branch by its name. Here the title toggles instead.
      if (new URL(link.href, window.location.href).pathname !== window.location.pathname) {
        window.location.href = link.href
        return
      }
    }

    const summary = event.target.closest("summary")
    if (!summary) return

    const details = summary.parentElement
    const reveal = details.querySelector(":scope > .reveal")
    if (!reveal || this.reduced.matches) return

    event.preventDefault()
    details.open ? this.close(details, reveal) : this.open(details, reveal)
  }

  open(details, reveal) {
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
