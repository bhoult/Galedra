import { Controller } from "@hotwired/stimulus"

// The 45-second film on the landing page (home/_film.html.erb, film.css).
// It plays once when half of it is in view and holds its last frame. It
// pauses while out of view or in a hidden tab, and resumes when back, unless
// the reader paused it. Pause and Replay are offered while it runs; with
// reduced motion it shows its last frame and a button to play it anyway.
const REDUCED = "(prefers-reduced-motion: reduce)"

export default class extends Controller {
  static targets = ["controls", "toggle", "replay"]

  connect() {
    this.started = false
    this.autoPaused = false
    this.inView = false
    this.element.classList.remove("is-playing", "is-paused", "is-done")
    this.onVisibility = () => this.autoPause(document.hidden || !this.inView)
    document.addEventListener("visibilitychange", this.onVisibility)
    this.controlsTarget.hidden = false
    this.toggleTarget.hidden = true

    if (window.matchMedia(REDUCED).matches) {
      this.replayTarget.textContent = "Play the film"
      this.inView = true // whoever presses play is looking at it
      return
    }
    this.replayTarget.textContent = "Replay"
    if (!("IntersectionObserver" in window)) {
      this.inView = true
      this.start()
      return
    }
    this.observer = new IntersectionObserver(([entry]) => {
      this.inView = entry.isIntersecting
      if (this.inView && !this.started) this.start()
      else this.autoPause(!this.inView)
    }, { threshold: 0.5 })
    this.observer.observe(this.element)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.observer?.disconnect()
  }

  toggle() {
    this.autoPaused = false
    this.setPaused(!this.element.classList.contains("is-paused"))
  }

  replay() {
    this.start()
  }

  ended(event) {
    if (event.animationName !== "fmClock") return
    this.element.classList.add("is-done")
    this.toggleTarget.hidden = true
  }

  // A fresh copy restarts every CSS animation from its first frame.
  start() {
    this.element.querySelectorAll(".film-stage, .film-progress").forEach((el) => el.replaceWith(el.cloneNode(true)))
    this.element.classList.remove("is-done")
    this.element.classList.add("is-playing")
    this.started = true
    this.autoPaused = false
    this.setPaused(false)
    this.toggleTarget.hidden = false
    this.replayTarget.textContent = "Replay"
  }

  setPaused(paused) {
    this.element.classList.toggle("is-paused", paused)
    this.toggleTarget.textContent = paused ? "Resume" : "Pause"
    this.toggleTarget.setAttribute("aria-pressed", paused ? "true" : "false")
  }

  autoPause(shouldPause) {
    if (!this.element.classList.contains("is-playing") || this.element.classList.contains("is-done")) return
    if (shouldPause && !this.element.classList.contains("is-paused")) {
      this.autoPaused = true
      this.setPaused(true)
    } else if (!shouldPause && this.autoPaused) {
      this.autoPaused = false
      this.setPaused(false)
    }
  }
}
