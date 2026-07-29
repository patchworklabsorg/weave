import { Controller } from "@hotwired/stimulus"

// Fills the hidden fingerprint/timezone fields on session-creating forms so
// new user_sessions records carry device data. FingerprintJS is loaded from a
// CDN <script> tag in the layout; if it failed to load (blocked, offline) the
// fields stay blank and login proceeds without them.
export default class extends Controller {
  static targets = ["fingerprint", "timezone"]

  connect() {
    if (this.hasTimezoneTarget) {
      try {
        this.timezoneTarget.value = Intl.DateTimeFormat().resolvedOptions().timeZone
      } catch {
        // leave blank
      }
    }
    this.fillFingerprint()
  }

  async fillFingerprint() {
    if (!this.hasFingerprintTarget || !window.FingerprintJS) return

    try {
      const fp = await window.FingerprintJS.load()
      const { visitorId } = await fp.get()
      this.fingerprintTarget.value = visitorId
    } catch {
      // leave blank
    }
  }
}
