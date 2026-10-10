import { Controller } from "@hotwired/stimulus"

// Reloads the /slack onboarding page when the person's step changes somewhere
// else, for example when they accept the Code of Conduct in Slack. Polls the
// status endpoint while the tab is visible, and stops after a while.
export default class extends Controller {
  static values = { url: String, step: String }

  connect() {
    this.checks = 0
    this.timer = setInterval(() => this.check(), 5000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async check() {
    if (document.hidden) return
    if (++this.checks > 120) return this.disconnect()

    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const { step } = await response.json()
      if (step !== this.stepValue) {
        this.disconnect()
        window.Turbo ? window.Turbo.visit(window.location.href, { action: "replace" }) : window.location.reload()
      }
    } catch {
      // A failed check is retried on the next tick.
    }
  }
}
