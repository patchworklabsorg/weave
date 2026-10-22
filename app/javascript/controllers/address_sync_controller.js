import { Controller } from "@hotwired/stimulus"

// "Billing address same as shipping" on the profile form. When checked, the
// billing fields drop their names (so nothing is posted for them) and go
// read-only; the hidden flag tells the server to copy the shipping address.
// The original name is kept on each input (data-name), so a reconnect after a
// Turbo cache restore still knows it.
export default class extends Controller {
  static targets = ["toggle", "flag"]

  connect() {
    this.billing = Array.from(this.element.querySelectorAll('[name*="billing_address"], [data-name*="billing_address"]'))
    this.shipping = Array.from(this.element.querySelectorAll('[name*="shipping_address"]'))
    this.billing.forEach((input) => { if (!input.dataset.name) input.dataset.name = input.name })

    const same = this.shipping.length > 0 && this.shipping.every((input, index) => {
      const partner = this.billing[index]
      return !partner || partner.value === input.value
    })
    if (same) this.toggleTarget.checked = true
    this.sync()
  }

  disconnect() {
    this.restore()
  }

  sync() {
    const checked = this.toggleTarget.checked
    this.flagTarget.value = checked ? "1" : "0"
    this.billing.forEach((input) => {
      input.name = checked ? "" : input.dataset.name
      input.readOnly = checked
      if (input.type === "checkbox") input.disabled = checked
    })
  }

  // Put the names back so a cached snapshot carries them.
  restore() {
    this.billing.forEach((input) => {
      input.name = input.dataset.name
      input.readOnly = false
      if (input.type === "checkbox") input.disabled = false
    })
  }
}
