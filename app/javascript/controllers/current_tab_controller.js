import { Controller } from "@hotwired/stimulus"

// Scrolls a row of tabs so the current tab is in view. The account tabs
// scroll sideways on a phone, and the last ones start off screen.
export default class extends Controller {
  connect() {
    const current = this.element.querySelector("[aria-current='page']")
    if (!current) return
    const row = this.element.getBoundingClientRect()
    const tab = current.getBoundingClientRect()
    if (tab.right > row.right) this.element.scrollLeft += tab.right - row.right + 16
  }
}
