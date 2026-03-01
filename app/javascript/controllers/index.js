// Auto-registers all Stimulus controllers from this directory via importmap's
// pin_all_from. Add a new *_controller.js file and it's available immediately.
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
