import { Controller } from "@hotwired/stimulus"

// "Billing address same as shipping" on the profile form. When checked, the
// billing fields drop their names (so nothing is posted for them) and go
// read-only; the hidden flag tells the server to copy the shipping address.
export default class extends Controller {
  static targets = ["toggle", "flag"]

  connect() {
    this.billing = Array.from(this.element.querySelectorAll('[name*="billing_address"]'))
    this.shipping = Array.from(this.element.querySelectorAll('[name*="shipping_address"]'))
    this.names = this.billing.map((input) => input.name)

    const same = this.shipping.length > 0 && this.shipping.every((input, index) => {
      const partner = this.billing[index]
      return !partner || partner.value === input.value
    })
    if (same) this.toggleTarget.checked = true
    this.sync()
  }

  sync() {
    const checked = this.toggleTarget.checked
    this.flagTarget.value = checked ? "1" : "0"
    this.billing.forEach((input, index) => {
      input.name = checked ? "" : this.names[index]
      input.readOnly = checked
      if (input.type === "checkbox") input.disabled = checked
    })
  }
}
