import { Controller } from "@hotwired/stimulus"

// Shows or hides a masked value, such as an OAuth client secret.
export default class extends Controller {
  static targets = ["output", "toggle"]
  static values = { secret: String, mask: String }

  toggle() {
    const visible = this.outputTarget.textContent === this.secretValue

    this.outputTarget.textContent = visible ? this.maskValue : this.secretValue
    this.toggleTarget.textContent = visible ? "👁️" : "🙈"
  }
}
