// The requester's side of break-glass (see key_custody/handoff.js).
//
// - ask: makes a one-time key pair, sends the reason and the public key, and
//   keeps the private key in IndexedDB under the new request id.
// - open: fetches the sealed data key and the encrypted image (once), opens
//   them with the private key, shows the image in the secure viewer, and
//   deletes the private key.
import { Controller } from "@hotwired/stimulus"
import { b64Decode, b64Encode, wipe } from "../key_custody/crypto"
import {
  decryptImage, deleteHandoffKey, generateHandoffKeyPair, loadHandoffKey, openSealedDataKey, storeHandoffKey
} from "../key_custody/handoff"
import { renderSecureImage } from "../lib/secure_viewer"

export default class extends Controller {
  static targets = ["reason", "status", "canvas", "button"]
  static values = { url: String, requestId: String, redirectUrl: String }

  async ask(event) {
    event.preventDefault()
    const reason = this.reasonTarget.value.trim()
    if (reason.length < 10) {
      this.say("Write the reason (at least 10 characters).")
      return
    }
    this.busy(true)
    try {
      const pair = await generateHandoffKeyPair()
      const data = await this.post(this.urlValue, { reason, requester_public_key: b64Encode(pair.publicKey) })
      await storeHandoffKey(data.id, pair)
      window.location.assign(data.redirect || this.redirectUrlValue)
    } catch (error) {
      this.say(`Stopped: ${error.message}`)
      this.busy(false)
    }
  }

  async open(event) {
    event.preventDefault()
    if (!window.confirm("Open the image now? You can open it only once. Opening it sends the notices.")) return
    this.busy(true)
    let dataKey = null
    try {
      const stored = await loadHandoffKey(this.requestIdValue)
      if (!stored) throw new Error("This browser does not have the key for this request. Ask again from the browser you will use.")
      this.say("Opening the image. This view is logged.")
      const handoff = await this.post(this.urlValue, {})
      dataKey = await openSealedDataKey(stored.privateKey, stored.publicKey, b64Decode(handoff.sealed_key), handoff.handoff_aad)
      const image = await decryptImage(dataKey, b64Decode(handoff.ciphertext), handoff.image_aad)
      await deleteHandoffKey(this.requestIdValue)
      this.clear = await renderSecureImage(this.canvasTarget, {
        bytes: image, contentType: handoff.content_type, watermark: handoff.watermark
      })
      wipe(image)
      this.say("The image shows only on this page, once. It blurs when you leave the window. Weave and this browser no longer hold its key.")
    } catch (error) {
      this.say(`Stopped: ${error.message}`)
      this.busy(false)
    } finally {
      wipe(dataKey)
    }
  }

  disconnect() {
    this.clear?.()
  }

  async post(url, body) {
    const response = await fetch(url, {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
      body: JSON.stringify(body),
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "Cache-Control": "no-store, no-cache",
        Pragma: "no-cache",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
      }
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(data.error || `The server answered ${response.status}.`)
    return data
  }

  busy(on) {
    if (this.hasButtonTarget) this.buttonTarget.disabled = on
  }

  say(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
