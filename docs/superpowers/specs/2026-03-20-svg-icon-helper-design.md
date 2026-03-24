# SVG Icon Helper Design

## Problem

~24 inline SVGs scattered across ERB templates and JS files. No abstraction
layer — every icon is raw markup pasted in place. The edit icon appears
verbatim in 5 templates; the plus icon in 5 more. Updating an icon means
hunting through views.

## Approach

**Helper method + constant hash** (Option A from brainstorming). A Ruby
`IconHelper` module with a frozen `ICONS` hash and a single `icon` method.
A parallel `icons.js` utility for the 3 JS-built icons.

Rejected alternatives:
- **SVG partials** — 15 tiny files, no JS help, partial overhead, harder
  to pass size/class overrides.
- **SVG sprite sheet** — `<use>` has `currentColor` quirks, different
  mental model, more complexity than ~15 icons warrant.

## Ruby Side

### `app/helpers/icon_helper.rb`

`ICONS` constant — frozen hash mapping symbol names to SVG definitions:

```ruby
ICONS = {
  edit:        { viewBox: '0 0 32 32', stroke_width: '2.5',
                 content: '<path d="M22 4l6 6-16 16H6v-6z"/>...' },
  plus:        { viewBox: '0 0 24 24', stroke_width: '2',
                 content: '<line x1="12" y1="5" x2="12" y2="19"/>...' },
  search:      { ... },
  settings:    { ... },
  book:        { ... },
  ingredients: { ... },
  menu:        { ... },
  cart:        { ... },
  tag:         { ... },
  sparkle:     { ... },
  apple:       { ... },
  scale:       { ... },
}.freeze
```

Each entry can carry per-icon default attributes (e.g. `stroke_width`) that
differ from the global defaults.

### `icon` method

```ruby
def icon(name, size: 24, **attrs)
```

Builds an inline `<svg>` tag with sensible defaults:
- `fill="none"`, `stroke="currentColor"`, `stroke-linecap="round"`,
  `stroke-linejoin="round"`, `aria-hidden="true"`
- `width` and `height` from `size:` — pass `size: nil` to omit both and
  let CSS control dimensions (used by nav icons via `.nav-icon`)
- Per-icon defaults (like `stroke-width`) merged under caller overrides
- No default `class` on the `<svg>` — callers add classes as needed

**Attribute naming.** The `ICONS` hash stores SVG attribute names as
string keys matching their actual SVG names (`'stroke-width'`, `viewBox`).
No underscore-to-hyphen translation — SVG mixes camelCase (`viewBox`) and
kebab-case (`stroke-width`), so a blanket conversion would break things.
Caller overrides use the same convention via keyword-to-string conversion
(e.g. `'stroke-width': '3'`).

**Accessibility.** Icons default to `aria-hidden="true"` (decorative).
For icons that convey meaning (e.g. ingredient status indicators), callers
pass `'aria-label': 'Has nutrition', 'aria-hidden': nil` to remove the
decorative default and add a label. Passing `nil` for any attribute removes
it from the output.

Caller examples:
- `<%= icon(:edit, size: 12) %>` — decorative, explicit size
- `<%= icon(:search, class: 'nav-icon', size: nil) %>` — CSS-sized nav icon
- `<%= icon(:apple, size: 14, class: 'ingredient-icon',
       'aria-label': 'Has nutrition', 'aria-hidden': nil) %>`

`.html_safe` is safe because content comes from our frozen constant, never
user input. Entry added to `html_safe_allowlist.yml`.

Raises `ArgumentError` on unknown icon names.

## JS Side

### `app/javascript/utilities/icons.js`

Plain object mapping names to definitions, plus a `buildIcon(name, size)`
function returning a DOM element via `createElementNS`.

3 icons: `chevron`, `delete`, `undo`.

`ordered_list_editor_utils.js` drops its three builder functions
(`chevronSvg`, `deleteSvg`, `undoSvg`) and imports from `icons.js`.
The `chevronSvg(flipped)` call becomes `buildIcon('chevron', 14)` with
the caller adding the `aisle-icon--flipped` class when needed.

The `download` icon in `nutrition_editor_controller.js` stays inline (single
use, already co-located).

## Scope

### Icons moving to the helper (ERB — 12 distinct, ~20 call sites)

| Icon          | Uses | Files                                           |
|---------------|------|-------------------------------------------------|
| `edit`        | 5    | recipes, menu, groceries, homepage, ingredients |
| `plus`        | 5    | homepage (2), groceries (2), custom items       |
| `search`      | 1    | nav                                             |
| `settings`    | 1    | nav                                             |
| `book`        | 2    | nav links (auth + unauth)                       |
| `ingredients` | 1    | nav links                                       |
| `menu`        | 1    | nav links                                       |
| `cart`        | 1    | nav links                                       |
| `tag`         | 1    | homepage                                        |
| `sparkle`     | 1    | homepage                                        |
| `apple`       | 1    | ingredients table                               |
| `scale`       | 1    | ingredients table                               |

### Icons moving to `icons.js` (3)

`chevron`, `delete`, `undo`

### Staying inline (special-case)

- **Hamburger** — CSS animation classes on individual `<rect>` elements
- **Availability dots** — conditional filled/hollow rendering with ERB logic

## Template Changes

Each inline SVG block replaced with `<%= icon(...) %>`. Surrounding markup
(buttons, links, classes) unchanged.

## Testing

Unit test for `IconHelper`:
- Returns valid SVG markup with correct tag structure
- Respects `size:` override
- `size: nil` omits width/height attributes
- Merges custom attributes (class, aria-label)
- Per-icon defaults (stroke-width) apply correctly
- Passing `nil` removes a default attribute
- Raises `ArgumentError` on unknown icon name

No integration/system tests — pure rendering helper.

## Files touched

- **New:** `app/helpers/icon_helper.rb`, `app/javascript/utilities/icons.js`,
  `test/helpers/icon_helper_test.rb`
- **Modified:** `app/views/shared/_nav.html.erb`,
  `app/views/shared/_nav_links.html.erb`, `app/views/homepage/show.html.erb`,
  `app/views/recipes/_recipe_content.html.erb`,
  `app/views/menu/show.html.erb`, `app/views/groceries/show.html.erb`,
  `app/views/groceries/_custom_items.html.erb`,
  `app/views/ingredients/_table_row.html.erb`,
  `app/javascript/utilities/ordered_list_editor_utils.js`,
  `config/html_safe_allowlist.yml`
