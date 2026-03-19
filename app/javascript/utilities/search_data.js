/**
 * Shared accessors for the pre-embedded search and smart-tag JSON blobs.
 * Both blobs live in <script type="application/json"> tags injected by
 * SearchDataHelper and SmartTagRegistry.
 *
 * Collaborators:
 * - search_overlay_controller.js: full-text recipe search
 * - dinner_picker_controller.js: weighted random recipe picker
 * - shared/_search_overlay.html.erb: search data script tag
 * - layouts/application.html.erb: smart-tag data script tag
 */

export function loadSearchData() {
  const el = document.querySelector("[data-search-overlay-target='data']")
  if (!el) return {}
  try { return JSON.parse(el.textContent || "{}") } catch { return {} }
}

export function loadSmartTagData() {
  const el = document.querySelector("[data-smart-tags]")
  if (!el) return {}
  try { return JSON.parse(el.textContent || "{}") } catch { return {} }
}
