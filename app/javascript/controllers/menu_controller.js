import { Controller } from "@hotwired/stimulus"

// A small popup menu: the account menu in the member top bar. The button
// toggles the panel (the hidden attribute). Opening moves focus to the
// first item. Escape or the button closes it and returns focus to the
// button; a click outside or a Turbo visit closes it too, and the menu is
// closed before Turbo caches the page, so Back never restores it open.
// Up, Down, Home and End move between items; Up or Down on the closed
// button opens the menu.
export default class extends Controller {
  static targets = ["button", "panel"]

  connect() {
    this.outside = (event) => { if (!this.element.contains(event.target)) this.close() }
    this.closeOnVisit = () => this.close()
    this.closeBeforeCache = () => this.set(false)
    document.addEventListener("click", this.outside)
    document.addEventListener("turbo:before-visit", this.closeOnVisit)
    document.addEventListener("turbo:before-cache", this.closeBeforeCache)
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
    document.removeEventListener("turbo:before-visit", this.closeOnVisit)
    document.removeEventListener("turbo:before-cache", this.closeBeforeCache)
  }

  toggle() {
    this.isOpen ? this.close({ focus: true }) : this.open()
  }

  open({ last = false } = {}) {
    this.set(true)
    const items = this.items
    items[last ? items.length - 1 : 0]?.focus()
  }

  close({ focus = false } = {}) {
    if (!this.isOpen) return
    this.set(false)
    if (focus) this.buttonTarget.focus()
  }

  keydown(event) {
    if (!this.isOpen) {
      if (event.target === this.buttonTarget && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
        event.preventDefault()
        this.open({ last: event.key === "ArrowUp" })
      }
      return
    }
    const items = this.items
    const index = items.indexOf(document.activeElement)
    if (event.key === "Escape") {
      event.preventDefault()
      this.close({ focus: true })
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      items[index < 0 ? 0 : (index + 1) % items.length]?.focus()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      items[index < 0 ? items.length - 1 : (index - 1 + items.length) % items.length]?.focus()
    } else if (event.key === "Home" || event.key === "End") {
      event.preventDefault()
      items[event.key === "Home" ? 0 : items.length - 1]?.focus()
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
