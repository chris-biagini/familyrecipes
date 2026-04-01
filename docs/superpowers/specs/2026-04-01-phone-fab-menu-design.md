# Phone FAB Menu

## Summary

Replace the top navbar with a floating action button (FAB) on phones. The FAB
is a circular hamburger icon fixed to the bottom center of the screen. Tapping
it expands a menu panel upward with a genie-style scale animation, revealing
nav links and icon buttons. The top navbar is completely hidden on phones.

"Phone" is defined by a CSS media query that combines touch detection, no-hover
capability, and a narrow viewport: `@media (pointer: coarse) and (hover: none)
and (max-width: 600px)`.

## Architecture

Two independent nav systems share the same data partials:

- **Top nav** (`_nav.html.erb` + `nav_menu_controller.js`) — existing,
  unchanged. Hidden via `display: none` in the phone media query.
- **Phone FAB** (`_phone_fab.html.erb` + `phone_fab_controller.js`) — new
  markup appended to the layout. Hidden by default, shown in the phone query.

Shared partials prevent drift between the two systems:

- `_nav_links.html.erb` — existing, renders Recipes/Ingredients/Menu/Groceries
- `_nav_icon_buttons.html.erb` — new, extracted from the inline icon buttons
  currently in `_nav.html.erb` (search, settings, help)

Both nav systems render these same partials. Only the layout CSS differs.

## Phone Detection

```css
@media (pointer: coarse) and (hover: none) and (max-width: 600px) { ... }
```

- `pointer: coarse` — touch screen (excludes desktop with mouse)
- `hover: none` — no hover capability (excludes touchscreen laptops)
- `max-width: 600px` — narrow viewport (excludes tablets)

All phone-specific styles and visibility toggles live inside this query.

## FAB Button

A circular button fixed to the bottom center of the viewport.

- **Position:** `fixed; bottom: calc(0.75rem + env(safe-area-inset-bottom, 0px)); left: 50%; transform: translateX(-50%)`
- **Size:** ~48px diameter
- **Appearance:** Frosted glass (`backdrop-filter: blur(10px)` + semi-transparent
  background matching the existing nav treatment), subtle box-shadow
- **Icon:** Same hamburger SVG (3 rects) used in the top nav. Reuses the
  existing `.hamburger-top/mid/bot` rotation transforms for the hamburger→X
  animation, driven by `aria-expanded`
- **Z-index:** 20
- **Stationary:** The button stays fixed in place during panel open/close

## Menu Panel

A fixed-position panel above the FAB containing the nav content.

### Layout

Top to bottom:
1. **Nav links** (`_nav_links` partial) — stacked vertically
2. **Divider** — thin horizontal rule
3. **Icon buttons** (`_nav_icon_buttons` partial) — horizontal row

### Positioning

- `position: fixed; bottom: calc(4rem + env(safe-area-inset-bottom, 0px))`
- `left: 50%; transform: translateX(-50%)`
- `width: min(85vw, 18rem)`
- Rounded corners, frosted glass background matching the FAB

### Open Animation (Genie — Scale + Slide Up)

- Panel starts at `scale(0.3) translateY(20px); opacity: 0` with
  `transform-origin: bottom center`
- Transitions to `scale(1) translateY(0); opacity: 1` over ~250ms with
  ease-out curve
- Nav link items get staggered fade-in: each delays ~30ms after the
  previous via a `--stagger` CSS custom property set by the controller
- Icon button row fades in last

### Close Animation (Reverse Genie)

- Same transition in reverse — panel scales down and fades toward the FAB
- No stagger on close — all items fade out together, then the panel shrinks

### Overlay

- Separate `div` with `position: fixed; inset: 0` behind the panel
- Semi-transparent dark background (`rgba(0,0,0,0.3)` — lighter than the
  search overlay)
- Fades in/out with the panel
- Tapping the overlay closes the menu

## Stimulus Controller

`phone_fab_controller.js` — owns the FAB button, panel, overlay, and all
phone menu interactions.

### Targets

- `button` — the FAB circle
- `panel` — the menu panel
- `overlay` — the dim backdrop
- `item` — each nav link/icon button (for stagger animation)

### Actions

- `toggle` — FAB tap, opens or closes
- `close` — overlay tap, Escape key, `turbo:before-visit`

### Open Flow

1. Set `aria-expanded="true"` on button (triggers hamburger→X CSS)
2. Remove `hidden` from overlay and panel
3. Next frame: add `.fab-open` class to panel (triggers scale/fade transition)
4. Set stagger delays on each item (`--stagger: 0`, `--stagger: 1`, etc.)
5. Trap focus within the panel

### Close Flow

1. Remove `.fab-open` from panel (triggers reverse animation)
2. Listen for `transitionend` on the panel
3. Set `hidden` on overlay and panel
4. Set `aria-expanded="false"` on button (triggers X→hamburger CSS)
5. Return focus to the FAB button

No ResizeObserver needed — the phone query handles visibility in pure CSS.
The controller just manages open/close state. If the FAB is hidden by CSS,
the controller is inert.

## Partial Extraction

The icon buttons (search, settings, help) are currently inline in
`_nav.html.erb`. Extract them into `_nav_icon_buttons.html.erb` so both nav
systems render the same source.

**Duplicate ID fix:** The settings button currently uses `id="settings-button"`.
With two copies in the DOM (top nav + FAB panel, though only one is visible),
switch to a Stimulus action or class-based selector to avoid duplicate IDs.

## CSS Adjustments

### Hide Top Nav on Phones

```css
@media (pointer: coarse) and (hover: none) and (max-width: 600px) {
  nav { display: none; }
}
```

### Gingham Top Spacing

With the nav hidden, add top padding to `main` so the gingham pattern is
still visible above the content. Exact value tuned visually — roughly the
same amount of gingham as when the nav is present.

### Scroll Margin

`scroll-margin-top: 3.5rem` on `#recipe-listings` and category filter targets
currently clears the sticky nav. Reduce to ~0.5rem in the phone query since
there is no sticky element to clear.

### Bottom Padding

Extra bottom padding on pages in the phone query so the FAB doesn't obscure
content: `padding-bottom: calc(5rem + env(safe-area-inset-bottom, 0px))`.

### Hidden Attribute Safety

The FAB and panel use the `hidden` attribute for their off-state. Since they
have explicit `display` values, add `[hidden] { display: none }` overrides
per the existing project convention.

## Edge Cases

### Search Button

Close FAB menu first, wait for `transitionend`, then dispatch to
`search-overlay#open`. Prevents visual collision between the two animations.

### Settings Button

Same close-then-dispatch pattern. Uses class-based selector or Stimulus
action instead of duplicate ID.

### Help Link

Standard `<a target="_blank">` — navigates away. FAB closes via
`turbo:before-visit` or just stays (user is leaving).

### Orientation Change

Rotating to landscape may exceed 600px width, causing the phone query to
stop matching. CSS handles this automatically — FAB hides, top nav shows.
Listen for `matchMedia` change or close on resize to clean up open state.

## Accessibility

- FAB: `aria-label="Menu"`, `aria-expanded` toggled by controller
- Panel: `role="dialog"`, `aria-label="Navigation"`
- Focus trap while open — Tab cycles through panel items only
- Escape closes menu and returns focus to FAB
- `prefers-reduced-motion: reduce` — skip scale/stagger, use simple opacity
  fade instead

## Reduced Motion

When `prefers-reduced-motion: reduce` matches, the genie scale animation and
staggered item fades are replaced with a simple opacity transition on the
panel. The hamburger→X icon animation is kept (it's subtle enough to not
cause issues).
