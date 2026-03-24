# iOS Editor Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Fix editor dialogs being cut off in PWA mode (#206) and scroll events not reaching editor content on iOS (#207).

**Architecture:** Make the `<dialog>` a non-scrolling flex frame with safe-area inset padding. Move scroll responsibility to individual content areas. One responsive path — no mobile-specific branching for these fixes.

**Tech Stack:** CSS only — no JS changes needed.

---

### Task 1: Make dialog a non-scrolling frame with safe-area insets

**Files:**
- Modify: `app/assets/stylesheets/style.css:1003-1016` (`.editor-dialog`, `.editor-dialog[open]`)

**Step 1: Add safe-area padding and overflow hidden**

In `.editor-dialog` (line 1003), change `padding: 0` to safe-area-aware padding:

```css
.editor-dialog {
  border: 1px solid var(--border-color);
  border-radius: 0.25rem;
  background: var(--content-background-color);
  padding: env(safe-area-inset-top, 0px) env(safe-area-inset-right, 0px) env(safe-area-inset-bottom, 0px) env(safe-area-inset-left, 0px);
  width: min(90vw, 50rem);
  max-height: 90vh;
  box-shadow: var(--shadow-dialog);
}
```

In `.editor-dialog[open]` (line 1013), add `overflow: hidden`:

```css
.editor-dialog[open] {
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
```

**Step 2: Run lint and tests**

Run: `bundle exec rubocop && rake test`
Expected: All pass (CSS-only change, no Ruby impact)

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "fix: add safe-area insets and overflow hidden to editor dialog"
```

---

### Task 2: Remove sticky positioning from header and footer

**Files:**
- Modify: `app/assets/stylesheets/style.css:1022-1032` (`.editor-header`)
- Modify: `app/assets/stylesheets/style.css:1211-1220` (`.editor-footer`)

**Step 1: Remove sticky from header**

Remove `position: sticky`, `top: 0`, `z-index: 1`, and `background` from `.editor-header`. The background was only needed for sticky overlap — the dialog background shows through now.

```css
.editor-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem 1.5rem;
  border-bottom: 1px solid var(--separator-color);
}
```

**Step 2: Remove sticky from footer**

Remove `position: sticky`, `bottom: 0`, and `background` from `.editor-footer`:

```css
.editor-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  padding: 1rem 1.5rem;
  border-top: 1px solid var(--separator-color);
}
```

**Step 3: Run tests**

Run: `rake test`
Expected: All pass

**Step 4: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "refactor: remove sticky positioning from editor header/footer"
```

---

### Task 3: Make content areas scroll with overscroll containment

**Files:**
- Modify: `app/assets/stylesheets/style.css` — `.editor-body` (new rule), `.aisle-order-body`, `.editor-textarea`

**Step 1: Add `.editor-body` rule**

This class wraps the nutrition editor's turbo-frame. Currently unstyled. Add after the `.editor-errors` rules (~line 1068):

```css
.editor-body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
}
```

**Step 2: Update `.aisle-order-body`**

Add `min-height: 0` and `overscroll-behavior: contain` to the existing rule (line 1227):

```css
.aisle-order-body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 0.75rem 1.5rem;
}
```

**Step 3: Add overscroll containment to textarea**

Add `overscroll-behavior: contain` to `.editor-textarea` (line 1070):

```css
.editor-textarea {
  flex: 1;
  min-height: 60vh;
  padding: 1.5rem;
  border: none;
  font-family: ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace;
  font-size: 0.85rem;
  line-height: 1.6;
  resize: none;
  outline: none;
  color: var(--text-color);
  background: var(--content-background-color);
  overscroll-behavior: contain;
}
```

**Step 4: Run tests**

Run: `rake test`
Expected: All pass

**Step 5: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "fix: contain scroll within editor content areas"
```

---

### Task 4: Clean up mobile media query

**Files:**
- Modify: `app/assets/stylesheets/style.css:1817-1909` (mobile `@media` block)

The mobile override for `.editor-dialog` currently sets `height: 100vh; max-height: 100vh`. These should use `100dvh` to account for iOS dynamic viewport (URL bar). The `overflow-x: hidden` can be removed since the dialog is now `overflow: hidden` from the base rule.

**Step 1: Update mobile dialog override**

```css
.editor-dialog {
  width: 100vw;
  max-width: 100vw;
  max-height: 100dvh;
  height: 100dvh;
  border-radius: 0;
  border: none;
}
```

Remove `overflow-x: hidden` (redundant — base rule has `overflow: hidden`).

**Step 2: Run tests**

Run: `rake test`
Expected: All pass

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "fix: use dynamic viewport height for mobile editor dialogs"
```

---

### Task 5: Wrap nutrition editor content in `.editor-body` on recipe show page

**Files:**
- Modify: `app/views/recipes/show.html.erb:33-37`

The nutrition editor on recipes/show already has `<div class="editor-body">` wrapping the turbo-frame. Verify the ingredients/index page does too.

**Step 1: Verify both nutrition editor instances**

Check `app/views/recipes/show.html.erb` — already has `<div class="editor-body">` (line 33).
Check `app/views/ingredients/index.html.erb` — already has `<div class="editor-body">` (line 34).

No HTML changes needed — the class is already in place, Task 3 adds the CSS.

**Step 2: Visual verification**

Start the dev server (`bin/dev`) and verify in a browser:
1. Recipe editor: opens full-height, textarea scrolls, header/footer visible
2. Nutrition editor: form content scrolls, Save button always reachable
3. QuickBites editor: textarea scrolls properly
4. Aisle/category editors: list scrolls, buttons always reachable
5. On mobile viewport (DevTools): dialog fills screen, no content cut off at edges

**Step 3: Commit (if any changes were needed)**

No commit expected — this is verification only.

---

### Task 6: Update `html_safe_allowlist.yml` if line numbers shifted

**Files:**
- Check: `config/html_safe_allowlist.yml`

**Step 1: Run the html_safe audit**

Run: `rake lint:html_safe`

If any violations are reported due to shifted line numbers, update the allowlist file.

**Step 2: Run full lint**

Run: `rake lint`
Expected: 0 offenses

**Step 3: Commit if needed**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist for shifted line numbers"
```
