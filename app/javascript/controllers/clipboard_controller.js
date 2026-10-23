import { Controller } from "@hotwired/stimulus"

// Copies a value to the clipboard. The CSP blocks inline onclick handlers,
// so copy buttons wire up through this controller instead. The button holds
// two icons, .copy-idle and .copy-done; the done one shows for a moment.
export default class extends Controller {
  static targets = ["button"]
  static values = { text: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
    } catch {
      return
    }
    if (!this.hasButtonTarget) return

    const idle = this.buttonTarget.querySelector(".copy-idle")
    const done = this.buttonTarget.querySelector(".copy-done")
    if (idle && done) {
      idle.hidden = true
      done.hidden = false
      clearTimeout(this.timer)
      this.timer = setTimeout(() => { idle.hidden = false; done.hidden = true }, 1500)
    } else {
      const label = this.buttonTarget.textContent
      this.buttonTarget.textContent = "Copied"
      setTimeout(() => { this.buttonTarget.textContent = label }, 1500)
    }
  }
}
