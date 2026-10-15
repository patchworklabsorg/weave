import { Controller } from "@hotwired/stimulus"
import {
  creationOptions,
  errorMessage,
  fetchOptions,
  passkeysSupported,
  serializeAttestation
} from "../lib/webauthn"

// Connects to data-controller="passkey-register"
//
// Adds a passkey on /profile/passkeys: gets the options from the server, has
// the device make the passkey, and posts the result in the form.
export default class extends Controller {
  static targets = ["credential", "button", "error", "unsupported"]
  static values = { optionsUrl: String }

  connect() {
    if (passkeysSupported()) return

    if (this.hasButtonTarget) this.buttonTarget.disabled = true
    if (this.hasUnsupportedTarget) this.unsupportedTarget.hidden = false
  }

  async register(event) {
    event.preventDefault()
    this.clearError()
    this.setBusy(true)

    try {
      const options = await fetchOptions(this.optionsUrlValue)
      const credential = await navigator.credentials.create({ publicKey: creationOptions(options) })
      if (!credential) throw new Error("No passkey was made")

      this.credentialTarget.value = serializeAttestation(credential)
      // submit(), not requestSubmit(): the submit event would start this again.
      this.element.submit()
    } catch (error) {
      this.showError(errorMessage(error))
      this.setBusy(false)
    }
  }

  setBusy(busy) {
    this.buttonTarget.disabled = busy
    this.buttonTarget.setAttribute("aria-busy", busy ? "true" : "false")
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }
}
