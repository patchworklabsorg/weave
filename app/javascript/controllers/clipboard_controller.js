import { Controller } from "@hotwired/stimulus"

// Copies a value to the clipboard. The CSP blocks inline onclick handlers,
// so copy buttons wire up through this controller instead.
export default class extends Controller {
  static targets = ["button"]
  static values = { text: String }

  async copy() {
    await navigator.clipboard.writeText(this.textValue)

    if (this.hasButtonTarget) {
      const label = this.buttonTarget.textContent
      this.buttonTarget.textContent = "✅"
      setTimeout(() => { this.buttonTarget.textContent = label }, 1500)
    }
  }
}
