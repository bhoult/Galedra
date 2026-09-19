import { Controller } from "@hotwired/stimulus"

// A description for a menu item, shown after the pointer has rested on it for
// a second. The delay is the point: a tooltip that appears the moment the
// pointer crosses a menu is noise while someone is only passing through.
//
// Anything carrying data-tip is eligible, so the markup decides what explains
// itself and this decides when. The browser's own title tooltip is the
// fallback when JavaScript does not run, and is removed here so that a person
// with JavaScript never sees both.
const DELAY = 1000

export default class extends Controller {
  connect() {
    this.tip = null
    this.timer = null
    this.current = null

    // Keyboard users get it immediately: they have already chosen the item,
    // so a delay would only be a wait.
    this.onEnter = (event) => this.schedule(event.target.closest("[data-tip]"), DELAY)
    this.onFocus = (event) => this.schedule(event.target.closest("[data-tip]"), 0)
    this.onLeave = () => this.hide()
    this.onKey = (event) => { if (event.key === "Escape") this.hide() }

    this.element.addEventListener("mouseover", this.onEnter)
    this.element.addEventListener("mouseout", this.onLeave)
    this.element.addEventListener("focusin", this.onFocus)
    this.element.addEventListener("focusout", this.onLeave)
    document.addEventListener("keydown", this.onKey)
    window.addEventListener("scroll", this.onLeave, { passive: true })

    // We are here, so the native tooltip would be a duplicate.
    this.titled = Array.from(this.element.querySelectorAll("[data-tip][title]"))
    this.titled.forEach((el) => el.removeAttribute("title"))
  }

  disconnect() {
    this.hide()
    this.element.removeEventListener("mouseover", this.onEnter)
    this.element.removeEventListener("mouseout", this.onLeave)
    this.element.removeEventListener("focusin", this.onFocus)
    this.element.removeEventListener("focusout", this.onLeave)
    document.removeEventListener("keydown", this.onKey)
    window.removeEventListener("scroll", this.onLeave)
    // Put the native tooltips back, so a page without this controller still
    // explains itself.
    this.titled.forEach((el) => { if (el.dataset.tip) el.setAttribute("title", el.dataset.tip) })
  }

  schedule(target, delay) {
    if (!target || target === this.current) return

    this.hide()
    this.timer = setTimeout(() => this.show(target), delay)
  }

  show(target) {
    if (!target.isConnected || !target.dataset.tip) return

    this.current = target
    this.tip = document.createElement("div")
    this.tip.className = "tooltip"
    this.tip.setAttribute("role", "tooltip")
    this.tip.id = `tip-${Math.random().toString(36).slice(2, 9)}`
    this.tip.textContent = target.dataset.tip
    document.body.appendChild(this.tip)
    target.setAttribute("aria-describedby", this.tip.id)
    this.place(target)
  }

  // Below the item, left-aligned with it, nudged back inside the viewport
  // rather than allowed to hang off the edge.
  place(target) {
    const rect = target.getBoundingClientRect()
    const width = this.tip.offsetWidth
    const margin = 8
    let left = rect.left
    if (left + width + margin > window.innerWidth) left = window.innerWidth - width - margin
    this.tip.style.left = `${Math.max(margin, left)}px`
    this.tip.style.top = `${rect.bottom + 6}px`
    this.tip.dataset.shown = "true"
  }

  hide() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    if (this.current) this.current.removeAttribute("aria-describedby")
    if (this.tip) this.tip.remove()
    this.tip = null
    this.current = null
  }
}
