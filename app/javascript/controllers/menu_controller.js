import { Controller } from "@hotwired/stimulus"

// Drop-down menus (Stage 24). Each menu is a <details>; only one stays open,
// and a click outside or Escape closes them. Without JavaScript they still
// open and close on their own.
// Opening on hover is for pointers. The test excludes touch rather than
// requiring a mouse: asking for "(hover: hover) and (pointer: fine)" sounds
// stricter but is answered false by environments that simply do not know, and
// then the menus quietly stop opening. A device with no pointer never fires
// mouseover on hover anyway, so being permissive here costs nothing.
const TOUCH = "(pointer: coarse)"
// Long enough not to open a menu the pointer is only crossing.
const OPEN_AFTER = 120
// Short enough to feel immediate, long enough to cross the gap between the
// summary and its panel without the menu closing underneath.
const CLOSE_AFTER = 220

export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.onToggle = (event) => this.closeOthers(event.target)
    this.onClick = (event) => { if (!this.element.contains(event.target)) this.closeAll() }
    this.onKey = (event) => { if (event.key === "Escape") this.closeAll() }
    this.itemTargets.forEach((item) => item.addEventListener("toggle", this.onToggle))
    document.addEventListener("click", this.onClick)
    document.addEventListener("keydown", this.onKey)

    if (window.matchMedia(TOUCH).matches) return

    this.timers = new Map()
    this.onOver = (event) => {
      const item = event.target.closest("details.menu")
      if (!item) return
      this.cancel(item)
      // A menu already open next door means the person is reading menus, so
      // move straight across rather than making them wait again.
      const delay = this.itemTargets.some((other) => other.open && other !== item) ? 0 : OPEN_AFTER
      this.timers.set(item, setTimeout(() => { item.open = true }, delay))
    }
    this.onOut = (event) => {
      const item = event.target.closest("details.menu")
      if (!item || item.contains(event.relatedTarget)) return
      this.cancel(item)
      this.timers.set(item, setTimeout(() => { item.open = false }, CLOSE_AFTER))
    }
    this.element.addEventListener("mouseover", this.onOver)
    this.element.addEventListener("mouseout", this.onOut)
  }

  cancel(item) {
    if (this.timers.has(item)) clearTimeout(this.timers.get(item))
    this.timers.delete(item)
  }

  disconnect() {
    this.itemTargets.forEach((item) => item.removeEventListener("toggle", this.onToggle))
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("keydown", this.onKey)
    if (!this.timers) return

    this.timers.forEach((t) => clearTimeout(t))
    this.timers.clear()
    this.element.removeEventListener("mouseover", this.onOver)
    this.element.removeEventListener("mouseout", this.onOut)
  }

  closeOthers(opened) {
    if (!opened.open) return
    this.itemTargets.forEach((item) => { if (item !== opened) item.open = false })
  }

  closeAll() {
    this.itemTargets.forEach((item) => { item.open = false })
  }
}
