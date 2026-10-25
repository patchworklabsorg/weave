import { Controller } from "@hotwired/stimulus"

// Fills the hidden fingerprint/timezone fields on session-creating forms so
// new user_sessions records carry device data. FingerprintJS is loaded from a
// deferred CDN <script> tag in the layout; if it failed to load (blocked,
// offline) the fields stay blank and login proceeds without them.
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
    this.whenLibraryReady(() => this.fillFingerprint())
  }

  disconnect() {
    this.script?.removeEventListener("load", this.onLoad)
  }

  // On a full page load the deferred library script runs after the module
  // bundle, so this controller usually connects first: wait for that script
  // element's load event. On a Turbo visit the library is already there.
  whenLibraryReady(callback) {
    if (window.FingerprintJS) return callback()
    this.script = document.querySelector('script[src*="fingerprintjs"]')
    if (!this.script) return callback()
    this.onLoad = () => callback()
    this.script.addEventListener("load", this.onLoad, { once: true })
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
