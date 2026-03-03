/**
 * Shared fetch-with-retry for Turbo Stream mutations. Sends JSON requests and
 * handles 204 No Content (broadcast-only) or Turbo Stream HTML responses.
 * Retries on network failure with exponential backoff (1s, 2s, 4s); shows a
 * toast via notify.js when the server returns an error or retries are exhausted.
 * Used by grocery_ui_controller and menu_controller.
 */
import { getCsrfToken } from "utilities/editor_utils"
import { show as notifyShow } from "utilities/notify"

class ServerError extends Error {}

export function sendAction(url, params, { method = "PATCH", retries = 3 } = {}) {
  return fetch(url, {
    method,
    headers: {
      "Content-Type": "application/json",
      "Accept": "text/vnd.turbo-stream.html",
      "X-CSRF-Token": getCsrfToken() || ""
    },
    body: JSON.stringify(params)
  })
    .then(response => {
      if (!response.ok) throw new ServerError()
      if (response.status === 204) return
      return response.text().then(html => {
        if (html.includes("<turbo-stream")) Turbo.renderStreamMessage(html)
      })
    })
    .catch(error => {
      if (error instanceof ServerError) {
        notifyShow("Something went wrong. Please try again.")
        return
      }
      if (retries <= 0) {
        notifyShow("Network error — your change may not have saved.")
        return
      }
      const delay = 1000 * Math.pow(2, 3 - retries)
      setTimeout(() => sendAction(url, params, { method, retries: retries - 1 }), delay)
    })
}
