import { Controller } from "@hotwired/stimulus"
import {
  conditionalMediationAvailable,
  errorMessage,
  fetchOptions,
  passkeysSupported,
  requestOptions,
  serializeAssertion
} from "../lib/webauthn"

// Connects to data-controller="passkey-sign-in"
//
// Signs in with a passkey in two ways. When the browser supports it, the email
// field offers saved passkeys as autofill (conditional mediation), so a person
// with a passkey never has to type an email. The "Sign in with a passkey"
// button asks for a passkey directly. Either way, the signed challenge goes to
// the server in the hidden form, and the server signs the person in.
export default class extends Controller {
  static targets = ["form", "credential", "button", "section", "error"]
  static values = { optionsUrl: String }

  connect() {
    if (!passkeysSupported()) {
      if (this.hasSectionTarget) this.sectionTarget.hidden = true
      return
    }

    if (this.hasSectionTarget) this.sectionTarget.hidden = false
    this.startAutofill()
  }

  disconnect() {
    this.abortPending()
  }

  async startAutofill() {
    if (!(await conditionalMediationAvailable())) return

    try {
      const controller = this.newAbortController()
      const options = await fetchOptions(this.optionsUrlValue)
      const credential = await navigator.credentials.get({
        publicKey: requestOptions(options),
        mediation: "conditional",
        signal: controller.signal
      })
      if (credential) this.submit(credential)
    } catch (error) {
      // An abort means the button took over. Other errors here are not worth
      // showing: the person did not ask for a passkey yet.
      if (error?.name !== "AbortError") console.warn("Passkey autofill stopped:", error)
    }
  }

  async signIn(event) {
    event.preventDefault()
    this.clearError()
    this.setBusy(true)

    try {
      const controller = this.newAbortController()
      const options = await fetchOptions(this.optionsUrlValue)
      const credential = await navigator.credentials.get({
        publicKey: requestOptions(options),
        signal: controller.signal
      })
      if (!credential) throw new Error("No passkey was returned")

      this.submit(credential)
    } catch (error) {
      if (error?.name === "AbortError") return

      this.showError(errorMessage(error))
      this.setBusy(false)
    }
  }

  submit(credential) {
    this.credentialTarget.value = serializeAssertion(credential)
    this.formTarget.requestSubmit()
  }

  // Only one WebAuthn request can be open at a time, so a new request ends the
  // one before it (usually the autofill request).
  newAbortController() {
    this.abortPending()
    this.abortController = new AbortController()
    return this.abortController
  }

  abortPending() {
    if (!this.abortController) return

    const error = new Error("A new passkey request started")
    error.name = "AbortError"
    this.abortController.abort(error)
    this.abortController = null
  }

  setBusy(busy) {
    if (!this.hasButtonTarget) return

    this.buttonTarget.disabled = busy
    this.buttonTarget.setAttribute("aria-busy", busy ? "true" : "false")
  }

  showError(message) {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }
}
