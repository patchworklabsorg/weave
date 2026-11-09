import { Controller } from "@hotwired/stimulus"

// A small popup menu: the account menu in the member top bar. The button
// toggles the panel (the hidden attribute). Opening moves focus to the
// first item; Escape, a click outside or a Turbo visit closes it, and
// Escape returns focus to the button. Up and Down move between items.
export default class extends Controller {
  static targets = ["button", "panel"]

  connect() {
    this.outside = (event) => { if (!this.element.contains(event.target)) this.close() }
    this.closeOnVisit = () => this.close()
    document.addEventListener("click", this.outside)
    document.addEventListener("turbo:before-visit", this.closeOnVisit)
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
    document.removeEventListener("turbo:before-visit", this.closeOnVisit)
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.set(true)
    this.items[0]?.focus()
  }

  close({ focus = false } = {}) {
    if (!this.isOpen) return
    this.set(false)
    if (focus) this.buttonTarget.focus()
  }

  keydown(event) {
    if (!this.isOpen) return
    if (event.key === "Escape") {
      event.preventDefault()
      this.close({ focus: true })
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const items = this.items
      const step = event.key === "ArrowDown" ? 1 : -1
      const index = items.indexOf(document.activeElement)
      items[(index + step + items.length) % items.length]?.focus()
    } else if (event.key === "Tab") {
      this.close()
    }
  }

  get isOpen() {
    return !this.panelTarget.hidden
  }

  // Visible items only: the section links hide past 64rem.
  get items() {
    return [...this.panelTarget.querySelectorAll("[role='menuitem']")].filter((item) => item.offsetParent !== null)
  }

  set(open) {
    this.panelTarget.hidden = !open
    this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
