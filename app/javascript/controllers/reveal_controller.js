import { Controller } from "@hotwired/stimulus"

// Shows or hides a masked value, such as an OAuth client secret. The toggle
// button holds two icons, .reveal-show and .reveal-hide.
export default class extends Controller {
  static targets = ["output", "toggle"]
  static values = { secret: String, mask: String }

  toggle() {
    const visible = this.outputTarget.textContent === this.secretValue
    this.outputTarget.textContent = visible ? this.maskValue : this.secretValue

    const show = this.toggleTarget.querySelector(".reveal-show")
    const hide = this.toggleTarget.querySelector(".reveal-hide")
    if (show && hide) {
      show.hidden = !visible
      hide.hidden = visible
    }
    this.toggleTarget.setAttribute("aria-pressed", String(!visible))
  }
}
