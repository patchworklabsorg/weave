import { Controller } from "@hotwired/stimulus"

// Opens and closes a panel that is hidden on small screens: the admin
// sidebar and the member nav sheet. The panel and the optional scrim carry
// data-open; the CSS does the rest.
export default class extends Controller {
  static targets = ["panel", "scrim", "button"]

  connect() {
    this.closeOnVisit = () => this.close()
    document.addEventListener("turbo:before-visit", this.closeOnVisit)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.closeOnVisit)
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.set(true)
  }

  close() {
    this.set(false)
  }

  keydown(event) {
    if (event.key === "Escape" && this.isOpen) this.close()
  }

  get isOpen() {
    return this.panelTarget.dataset.open === "true"
  }

  set(open) {
    this.panelTarget.dataset.open = String(open)
    if (this.hasScrimTarget) this.scrimTarget.dataset.open = String(open)
    this.buttonTargets.forEach((button) => button.setAttribute("aria-expanded", String(open)))
  }
}
