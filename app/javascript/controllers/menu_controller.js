import { Controller } from "@hotwired/stimulus"

// Drop-down menus (Stage 24). Each menu is a <details>; only one stays open,
// and a click outside or Escape closes them. Without JavaScript they still
// open and close on their own.
export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.onToggle = (event) => this.closeOthers(event.target)
    this.onClick = (event) => { if (!this.element.contains(event.target)) this.closeAll() }
    this.onKey = (event) => { if (event.key === "Escape") this.closeAll() }
    this.itemTargets.forEach((item) => item.addEventListener("toggle", this.onToggle))
    document.addEventListener("click", this.onClick)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    this.itemTargets.forEach((item) => item.removeEventListener("toggle", this.onToggle))
    document.removeEventListener("click", this.onClick)
    document.removeEventListener("keydown", this.onKey)
  }

  closeOthers(opened) {
    if (!opened.open) return
    this.itemTargets.forEach((item) => { if (item !== opened) item.open = false })
  }

  closeAll() {
    this.itemTargets.forEach((item) => { item.open = false })
  }
}
