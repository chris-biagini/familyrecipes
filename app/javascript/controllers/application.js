/**
 * Stimulus application instance shared by all controllers. Imported by
 * controllers/index.js for eager-loading and by individual controllers
 * that need direct Application access.
 */
import { Application } from "@hotwired/stimulus"

const application = Application.start()
application.debug = false
window.Stimulus = application

export { application }
