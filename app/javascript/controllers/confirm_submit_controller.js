import { Controller } from "@hotwired/stimulus"

// Asks before a form submits. For forms with Turbo off, where
// data-turbo-confirm does nothing. The CSP blocks inline handlers, so the
// form wires up through this controller.
export default class extends Controller {
  static values = { message: String }

  submit(event) {
    if (!window.confirm(this.messageValue)) event.preventDefault()
  }
}
