import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Turbo's progress bar uses inline styles, which our CSP blocks.
Turbo.config.drive.progressBarDelay = Infinity

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js')
}
