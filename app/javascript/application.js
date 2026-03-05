/**
 * JS entry point. Boots Turbo Drive + Stimulus (via controllers/index.js) and
 * registers the service worker. Turbo progress bar styles live in style.css
 * (not Turbo's dynamic <style> injection) to satisfy our strict CSP.
 * Pinned in config/importmap.rb as "application".
 */
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

Turbo.config.drive.progressBarDelay = 300

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js')
}
