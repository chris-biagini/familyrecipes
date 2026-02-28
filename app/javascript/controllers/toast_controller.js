import { Controller } from "@hotwired/stimulus"
import { show as notifyShow } from "utilities/notify"

export default class extends Controller {
  static values = { message: String }

  connect() {
    notifyShow(this.messageValue)
    this.element.remove()
  }
}
