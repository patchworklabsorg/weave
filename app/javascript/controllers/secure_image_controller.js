// Shows an ID image in the secure viewer (see lib/secure_viewer.js). The
// "show" action fetches the bytes from urlValue (a POST that Weave logs) and
// draws them in the canvas with the watermark.
import { Controller } from "@hotwired/stimulus"
import { base64ToBytes, fetchSecureImage, renderSecureImage } from "../lib/secure_viewer"

export default class extends Controller {
  static targets = ["canvas", "status", "button"]
  static values = { url: String, confirm: String }

  async show(event) {
    event.preventDefault()
    if (this.confirmValue && !window.confirm(this.confirmValue)) return
    if (this.hasButtonTarget) this.buttonTarget.disabled = true
    this.say("Opening the image. This view is logged.")
    try {
      const image = await fetchSecureImage(this.urlValue)
      const bytes = base64ToBytes(image.data)
      image.data = null
      this.clear?.()
      this.clear = await renderSecureImage(this.canvasTarget, {
        bytes, contentType: image.content_type, watermark: image.watermark
      })
      bytes.fill(0)
      this.say("The image shows only on this page. It blurs when you leave the window.")
    } catch (error) {
      this.say(`Stopped: ${error.message}`)
      if (this.hasButtonTarget) this.buttonTarget.disabled = false
    }
  }

  disconnect() {
    this.clear?.()
  }

  say(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
