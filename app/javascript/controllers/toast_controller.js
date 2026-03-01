import { Controller } from "@hotwired/stimulus"
import { show as notifyShow } from "utilities/notify"

/**
 * Fire-and-forget toast notification. Shows a message on connect and immediately
 * removes itself from the DOM. Used by RecipeBroadcaster's Turbo Stream
 * broadcasts — the server appends a <div data-controller="toast"> to trigger
 * a notification on all connected clients.
 */
export default class extends Controller {
  static values = { message: String }

  connect() {
    notifyShow(this.messageValue)
    this.element.remove()
  }
}
