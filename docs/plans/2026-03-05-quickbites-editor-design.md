# QuickBites Editor Enhancement — Design

## Goal

Add creature comforts to the QuickBites textarea editor: syntax highlighting, auto-dash on Enter, and placeholder example text. Keep it simple — proactive polish, not a full rewrite.

## What changes

### 1. Syntax-highlighted overlay

Replace the plain textarea with a textarea + transparent overlay approach. The textarea remains the actual input, but a `<pre>` element behind it renders the same text with color-coded spans:

- **Category headers** (`Snacks:`) — bold, accent color
- **Item names** (`- Peanut Butter on Bread`) — default text color
- **Ingredients** (`: Peanut butter, Bread`) — muted/secondary color after the colon
- **Unrecognized lines** — no special treatment (warnings on save handle it)

Classic "transparent textarea over colored pre" technique. No contentEditable, no custom cursor management. The textarea is always the real input; the overlay is purely decorative.

### 2. Auto-dash on Enter

When the user presses Enter while the cursor is on a line that starts with `- `, the new line automatically gets `- ` prepended. If they press Enter on an empty `- ` line (just want to end the list), it removes the dash and leaves a blank line. Standard list-continuation UX (same as Notion/Obsidian).

### 3. Placeholder example

When content is empty, show a placeholder demonstrating the format:

```
Snacks:
- Hummus with Pretzels: Hummus, Pretzels
- String cheese

Breakfast:
- Cereal with Milk: Cereal, Milk
```

## What doesn't change

- Save/load flow (generic editor controller)
- Parse warnings after save
- No live error indicators
- No auto-newline after category headers

## Implementation approach

A new Stimulus controller (`quickbites-editor`) that attaches alongside the existing `editor` controller. It:

- Creates the `<pre>` overlay behind the textarea on connect
- Syncs overlay content on every `input` event via `highlightContent()`
- Handles `keydown` for Enter (auto-dash logic)
- Sets the placeholder attribute on the textarea

The overlay uses the same font/size/padding as the textarea so text aligns perfectly. The textarea gets `color: transparent; caret-color: var(--text-color)` so the user sees the colored overlay text but types into the real textarea.

CSS lives in `style.css` alongside existing editor styles. Colors use CSS variables for dark/light theme support.

### Scroll sync

The overlay `<pre>` must scroll in lockstep with the textarea. On `scroll` event, copy `scrollTop` and `scrollLeft` from textarea to overlay.

### File changes

- `app/javascript/controllers/quickbites_editor_controller.js` — new Stimulus controller
- `app/assets/stylesheets/style.css` — overlay positioning, highlight colors
- `app/views/menu/show.html.erb` — add `data-controller="quickbites-editor"` and target to the textarea area
