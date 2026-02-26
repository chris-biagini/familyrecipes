import "@hotwired/turbo-rails"
import "controllers"

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js')
}
