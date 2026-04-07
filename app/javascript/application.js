/**
 * Esbuild entry point. Boots Turbo Drive + Stimulus, explicitly registers all
 * controllers, and manages global Turbo lifecycle handlers: morph protection
 * for open dialogs and pre-cache cleanup. Also registers the service worker.
 */
import { Turbo } from "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"

const application = Application.start()
application.debug = false
window.Stimulus = application

import AiImportController from "./controllers/ai_import_controller"
import DinnerPickerController from "./controllers/dinner_picker_controller"
import DualModeEditorController from "./controllers/dual_mode_editor_controller"
import EditorController from "./controllers/editor_controller"
import GroceryUiController from "./controllers/grocery_ui_controller"
import ImportController from "./controllers/import_controller"
import IngredientTableController from "./controllers/ingredient_table_controller"
import MenuController from "./controllers/menu_controller"
import NavMenuController from "./controllers/nav_menu_controller"
import NutritionEditorController from "./controllers/nutrition_editor_controller"
import OrderedListEditorController from "./controllers/ordered_list_editor_controller"
import PhoneFabController from "./controllers/phone_fab_controller"
import PlaintextEditorController from "./controllers/plaintext_editor_controller"
import QuickbitesGraphicalController from "./controllers/quickbites_graphical_controller"
import RecipeFilterController from "./controllers/recipe_filter_controller"
import RecipeGraphicalController from "./controllers/recipe_graphical_controller"
import RecipeStateController from "./controllers/recipe_state_controller"
import RevealController from "./controllers/reveal_controller"
import ScalePanelController from "./controllers/scale_panel_controller"
import SearchOverlayController from "./controllers/search_overlay_controller"
import SettingsEditorController from "./controllers/settings_editor_controller"
import TagInputController from "./controllers/tag_input_controller"
import ToastController from "./controllers/toast_controller"
import WakeLockController from "./controllers/wake_lock_controller"

application.register("ai-import", AiImportController)
application.register("dinner-picker", DinnerPickerController)
application.register("dual-mode-editor", DualModeEditorController)
application.register("editor", EditorController)
application.register("grocery-ui", GroceryUiController)
application.register("import", ImportController)
application.register("ingredient-table", IngredientTableController)
application.register("menu", MenuController)
application.register("nav-menu", NavMenuController)
application.register("nutrition-editor", NutritionEditorController)
application.register("ordered-list-editor", OrderedListEditorController)
application.register("phone-fab", PhoneFabController)
application.register("plaintext-editor", PlaintextEditorController)
application.register("quickbites-graphical", QuickbitesGraphicalController)
application.register("recipe-filter", RecipeFilterController)
application.register("recipe-graphical", RecipeGraphicalController)
application.register("recipe-state", RecipeStateController)
application.register("reveal", RevealController)
application.register("scale-panel", ScalePanelController)
application.register("search-overlay", SearchOverlayController)
application.register("settings-editor", SettingsEditorController)
application.register("tag-input", TagInputController)
application.register("toast", ToastController)
application.register("wake-lock", WakeLockController)

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

// Smooth-scroll only for in-page fragment links (e.g. href="#section").
// Global scroll-behavior:smooth on <html> also animates Turbo's scroll
// restoration on page navigation, causing a visible slide-to-top. (GH #350)
document.addEventListener("click", (event) => {
  const anchor = event.target.closest("a[href^='#']")
  if (!anchor) return

  const id = anchor.getAttribute("href").slice(1)
  const target = document.getElementById(id)
  if (target) {
    event.preventDefault()
    target.scrollIntoView({ behavior: "smooth" })
  }
})

// iOS standalone PWA workaround: WebKit skips touch event dispatch after
// Turbo replaces the body during back-navigation when no document-level
// touchstart listener exists. This empty listener keeps the touch pipeline
// active so the first tap isn't swallowed. (GH #346)
document.addEventListener("touchstart", () => {}, { passive: true, capture: true })
