import { Controller } from "@hotwired/stimulus"

// Puts the browser's time zone in a hidden form field and names it in the
// hint, so a person can type a time in their own zone. Without JavaScript
// the field stays "UTC" and the server reads the time as UTC.
export default class extends Controller {
  static targets = ["field", "label"]

  connect() {
    let zone
    try {
      zone = Intl.DateTimeFormat().resolvedOptions().timeZone
    } catch {
      return
    }
    if (!zone) return

    this.fieldTargets.forEach((field) => { field.value = zone })
    this.labelTargets.forEach((label) => { label.textContent = zone.replaceAll("_", " ") })
  }
}
