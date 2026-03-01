/**
 * JS entry point. Boots Turbo Drive + Stimulus (via controllers/index.js) and
 * registers the service worker. Turbo's progress bar is disabled because CSP
 * blocks its inline styles. Pinned in config/importmap.rb as "application".
 */
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Turbo's progress bar uses inline styles, which our CSP blocks.
Turbo.config.drive.progressBarDelay = Infinity

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js')
}
