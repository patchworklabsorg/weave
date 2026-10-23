import { Controller } from "@hotwired/stimulus"

// Flash messages render as toasts (shared/_flash). Each one leaves on its
// own after `duration` ms, pauses while hovered, and closes on its button.
export default class extends Controller {
  static targets = ["toast"]
  static values = { duration: { type: Number, default: 6000 } }

  connect() {
    this.timers = new Map()
    this.toastTargets.forEach((toast) => this.schedule(toast))
  }

  disconnect() {
    this.timers.forEach((timer) => clearTimeout(timer))
  }

  dismiss(event) {
    this.leave(event.currentTarget.closest("[data-flash-target='toast']"))
  }

  pause(event) {
    clearTimeout(this.timers.get(event.currentTarget))
  }

  resume(event) {
    this.schedule(event.currentTarget)
  }

  schedule(toast) {
    toast.style.setProperty("--toast-duration", `${this.durationValue}ms`)
    this.timers.set(toast, setTimeout(() => this.leave(toast), this.durationValue))
  }

  leave(toast) {
    if (!toast || toast.classList.contains("is-leaving")) return
    clearTimeout(this.timers.get(toast))
    toast.classList.add("is-leaving")
    toast.addEventListener("animationend", () => toast.remove(), { once: true })
    // Reduced motion ends the animation at once, so remove on a short timer too.
    setTimeout(() => toast.remove(), 400)
  }
}
