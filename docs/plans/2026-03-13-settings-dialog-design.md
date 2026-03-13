# Settings Dialog Design

## Goal

Move settings from a standalone page to an editor `<dialog>`, matching the
pattern used by recipe, quick bites, and nutrition editors. Remove all legacy
settings-page artifacts.

## Approach

### Dialog placement and trigger

The settings dialog renders in the application layout (guarded by `logged_in?`).
The nav gear icon becomes a `<button>` with a data-action that opens the dialog
via the editor controller's open-selector mechanism.

### Editor pattern integration

Uses `render layout: 'shared/editor_dialog'` with a companion
`settings_editor_controller` Stimulus controller. The editor controller handles
open/close/save lifecycle; the companion handles form-specific concerns:

- `editor:collect` — gathers form field values into a JSON payload
- `editor:save` — provides a custom `saveFn` (structured form, not textarea)
- `editor:modified` — compares current field values against originals
- `editor:reset` — restores original values on cancel

### Data flow

1. User clicks gear button — editor opens, fetches current values from
   `GET /settings` (JSON)
2. User edits fields, clicks Save
3. `settings_editor_controller` collects fields, sends `PATCH /settings` (JSON)
4. `SettingsController#update` saves, returns JSON success/error
5. `onSuccess: 'reload'` — full page reload reflects updated site title

### Controller changes

`SettingsController` becomes JSON-only:

- `show` returns current settings as JSON (for dialog load)
- `update` accepts JSON, returns JSON response with success/errors
- Remove the HTML `show` template and redirect-based flow

### What gets removed

- `app/views/settings/show.html.erb`
- All `.settings-page`, `.settings-section`, `.settings-field`, `.settings-input`,
  `.settings-form`, `.settings-actions`, `.settings-api-key-row`,
  `.settings-reveal-btn`, `.flash-notice` CSS
- The `<a>` link in `_nav.html.erb` (replaced by `<button>`)

### What stays

- `reveal_controller` for the API key show/hide toggle
- Same four fields: site_title, homepage_heading, homepage_subtitle, usda_api_key
- `require_membership` guard on the controller

### Form markup inside dialog

Simple labeled inputs in an `.editor-body` div, using shared editor classes
plus minimal `.settings-field` styling for spacing. The API key row retains
its reveal toggle. No textarea — the editor controller's textarea target is
unused; all data flows through the companion controller's event hooks.
