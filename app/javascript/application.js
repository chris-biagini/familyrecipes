/**
 * JS entry point. Boots Turbo Drive + Stimulus (via controllers/index.js) and
 * registers the service worker. Also manages global Turbo lifecycle handlers:
 * morph protection for open dialogs (broadcast refresh) and pre-cache cleanup.
 * Pinned in config/importmap.rb as "application".
 */
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

Turbo.config.drive.progressBarDelay = 300

// Protect open dialogs from Turbo morph (broadcast refresh) without using
// data-turbo-permanent, which also blocks replacement during navigation
// and causes stale editor content when moving between pages.
document.addEventListener("turbo:before-morph-element", (event) => {
  if (event.target.tagName === "DIALOG" && event.target.open) {
    event.preventDefault()
  }
})

// Close all open dialogs before Turbo caches the page. Prevents cached
// snapshots from restoring stale open dialogs with detached listeners.
document.addEventListener("turbo:before-cache", () => {
  document.querySelectorAll("dialog[open]").forEach(dialog => dialog.close())
})

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js')
}
