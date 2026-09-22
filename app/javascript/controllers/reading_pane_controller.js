import { Controller } from "@hotwired/stimulus"

// Take the reader to what they chose, when the outline is above it rather than
// beside it.
//
// Choosing a section loads the reading pane in place through a Turbo frame,
// which is what keeps the outline from being fetched again and lets it animate.
// On a wide screen the two sit side by side and the new content is already in
// view. Stacked on a phone, nothing moves: the outline still fills the screen
// and the section you asked for is somewhere below it. The page looked broken
// for that reason alone (owner, 2026-09-22).
//
// Only when the columns have stacked, because on a wide screen this would be an
// unasked-for jump. Anyone who has asked for less motion is taken there without
// the animation, not left behind.
const STACKED = "(max-width: 56rem)"

export default class extends Controller {
  connect() {
    this.onLoad = () => this.reveal()
    this.element.addEventListener("turbo:frame-load", this.onLoad)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this.onLoad)
  }

  reveal() {
    if (!window.matchMedia(STACKED).matches) return

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.element.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "start" })
  }
}
