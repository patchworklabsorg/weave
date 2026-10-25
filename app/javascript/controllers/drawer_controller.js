import { Controller } from "@hotwired/stimulus"

// Opens and closes a panel that is hidden on small screens: the admin
// sidebar and the member nav sheet. The panel and the optional scrim carry
// data-open; the CSS does the rest. The panel may be absent (a signed-out
// top bar has no menu), so every method checks for it.
//
// Keyboard: opening moves focus to the first link in the panel, closing
// returns it to the button that opened it. An optional content target
// (the admin main column) goes inert while the panel is open, so Tab stays
// inside the drawer.
export default class extends Controller {
  static targets = ["panel", "scrim", "button", "content"]

  connect() {
    this.closeOnVisit = () => this.close()
    document.addEventListener("turbo:before-visit", this.closeOnVisit)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.closeOnVisit)
    this.contentTargets.forEach((content) => content.removeAttribute("inert"))
  }

  toggle(event) {
    this.isOpen ? this.close() : this.open(event)
  }

  open(event) {
    if (!this.hasPanelTarget || this.isOpen) return
    this.opener = event?.currentTarget || document.activeElement
    this.set(true)
    this.panelTarget.querySelector("a, button, [tabindex='0']")?.focus()
  }

  close() {
    if (!this.isOpen) return
    this.set(false)
    this.opener?.focus()
    this.opener = null
  }

  keydown(event) {
    if (event.key === "Escape" && this.isOpen) this.close()
  }

  get isOpen() {
    return this.hasPanelTarget && this.panelTarget.dataset.open === "true"
  }

  set(open) {
    if (!this.hasPanelTarget) return
    this.panelTarget.dataset.open = String(open)
    if (this.hasScrimTarget) this.scrimTarget.dataset.open = String(open)
    this.buttonTargets.forEach((button) => button.setAttribute("aria-expanded", String(open)))
    this.contentTargets.forEach((content) => content.toggleAttribute("inert", open))
  }
}
