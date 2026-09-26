import { Controller } from "@hotwired/stimulus"

// Two things every page wants and no page should have to ask for, applied to
// the body and to anything loaded into it later (the outline's reading pane is
// a Turbo frame, so its contents arrive after connect).
//
// 1. Tables that read on a phone. Each data cell is labelled with its column's
//    heading, and the table is marked `stack`; below tablet width the CSS then
//    lays each row out as a card of label/value lines instead of squeezing
//    every column into a strip a word wide. A table marked `keep` is left as a
//    table (Swagger's, and any whose meaning is its grid).
//
// 2. A copy button on anything a person would paste somewhere else: every
//    <pre>, and any element carrying data-copy (a token, an address, a share
//    line). Copying the text is the point; selecting a 60-character token by
//    hand on a phone is the thing it replaces.
// Fixed markup, never built from page text.
const COPY_ICON = '<svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>'
const COPIED_ICON = '<svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>'

export default class extends Controller {
  connect() {
    this.enhance(this.element)
    this.observer = new MutationObserver((records) => {
      for (const record of records) {
        record.addedNodes.forEach((node) => { if (node.nodeType === 1) this.enhance(node) })
      }
    })
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  enhance(root) {
    const tables = root.matches?.("table") ? [ root ] : root.querySelectorAll?.("table") || []
    tables.forEach((table) => this.label(table))
    const copyables = [ ...(root.matches?.("pre, [data-copy]") ? [ root ] : []), ...(root.querySelectorAll?.("pre, [data-copy]") || []) ]
    copyables.forEach((el) => this.addCopy(el))
  }

  label(table) {
    if (table.classList.contains("keep") || table.classList.contains("stack") || table.closest(".swagger-ui")) return
    const rows = [ ...table.rows ]
    if (rows.length === 0) return
    // The heading row: the thead's, or a first row made only of <th>.
    const head = table.tHead?.rows[0] || ([ ...rows[0].cells ].every((c) => c.tagName === "TH") ? rows[0] : null)
    const labels = []
    if (head) {
      head.classList.add("head")
      for (const cell of head.cells) {
        const text = cell.innerText.trim()
        for (let i = 0; i < (cell.colSpan || 1); i++) labels.push(text)
      }
    }
    for (const row of rows) {
      if (row === head) continue
      let col = 0
      for (const cell of row.cells) {
        if (labels[col] && !cell.dataset.label && cell.tagName === "TD") {
          cell.dataset.label = labels[col]
          // One element holding the value, so label and value can be the two
          // columns of a grid that grows to whichever is taller. A label drawn
          // in absolute position overlapped the next row whenever it wrapped.
          const value = document.createElement("span")
          value.className = "cell-value"
          while (cell.firstChild) value.appendChild(cell.firstChild)
          cell.appendChild(value)
        }
        col += cell.colSpan || 1
      }
    }
    table.classList.add("stack")
  }

  addCopy(el) {
    if (el.dataset.copyReady || el.closest(".swagger-ui")) return
    el.dataset.copyReady = "1"
    // An icon, not a word (owner, 2026-09-23): in the top right corner of a
    // block (a <pre>, a share line), and beside an inline value. What it does
    // is in its label and tooltip, and a tick replaces it for a moment once the
    // text is on the clipboard.
    const button = document.createElement("button")
    button.type = "button"
    button.className = "copy-button"
    button.innerHTML = COPY_ICON
    button.title = "Copy"
    button.setAttribute("aria-label", "Copy to clipboard")
    button.addEventListener("click", async (event) => {
      event.preventDefault()
      const text = (el.dataset.copy && el.dataset.copy !== "" ? el.dataset.copy : el.innerText).trim()
      const done = await this.write(text)
      button.innerHTML = done ? COPIED_ICON : COPY_ICON
      button.title = done ? "Copied" : "Select the text and copy it"
      button.classList.toggle("copied", done)
      setTimeout(() => { button.innerHTML = COPY_ICON; button.title = "Copy"; button.classList.remove("copied") }, 1800)
    })
    const block = el.tagName === "PRE" || el.classList.contains("share-line")
    if (block) {
      const wrap = document.createElement("div")
      wrap.className = "copy-wrap"
      el.parentNode.insertBefore(wrap, el)
      wrap.appendChild(el)
      wrap.appendChild(button)
    } else {
      button.classList.add("inline")
      el.insertAdjacentElement("afterend", button)
    }
  }

  // The async clipboard needs a secure context and a user gesture; the
  // textarea fallback covers an http development host and older WebViews.
  async write(text) {
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text)
        return true
      }
    } catch (_) { /* fall through */ }
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.appendChild(area)
    area.select()
    let ok = false
    try { ok = document.execCommand("copy") } catch (_) { ok = false }
    area.remove()
    return ok
  }
}
