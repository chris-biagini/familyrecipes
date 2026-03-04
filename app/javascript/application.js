/**
 * JS entry point. Boots Turbo Drive + Stimulus (via controllers/index.js) and
 * registers the service worker. Turbo progress bar styles live in style.css
 * (not Turbo's dynamic <style> injection) to satisfy our strict CSP.
 * Pinned in config/importmap.rb as "application".
 */
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

Turbo.config.drive.progressBarDelay = 300

// Preserve <details> open state across Turbo Stream replacements.
// Page-refresh morphs are handled per-controller; this covers targeted
// stream broadcasts (e.g., recipe edits replacing the recipe-selector).
document.addEventListener("turbo:before-stream-render", (event) => {
  const openDetails = document.querySelectorAll("details[open]")
  if (!openDetails.length) return

  const snapshot = Array.from(openDetails).map(d => ({
    id: d.id,
    ariaLabel: d.querySelector("summary")?.getAttribute("aria-label"),
    dataAisle: d.dataset?.aisle
  }))

  const originalRender = event.detail.render
  event.detail.render = async (...args) => {
    await originalRender(...args)
    snapshot.forEach(({ id, ariaLabel, dataAisle }) => {
      const match = (id && document.getElementById(id))
        || (ariaLabel && document.querySelector(`details summary[aria-label="${CSS.escape(ariaLabel)}"]`)?.closest("details"))
        || (dataAisle && document.querySelector(`details[data-aisle="${CSS.escape(dataAisle)}"]`))
      if (match) match.open = true
    })
  }
})

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js')
}
