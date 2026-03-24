# Dual-Mode Editor: New Recipe Initialization Fix

**Issue:** GH #273
**Date:** 2026-03-21

## Problem

The new recipe dialog's dual-mode editor has two mode-switching bugs:

1. **Graphical → Text produces blank editor.** The graphical form starts
   empty, so serializing it yields empty/minimal markdown.

2. **Text → Graphical treats template as content.** The plaintext template
   ("Recipe Title", "Optional description", etc.) is parsed as real data and
   loaded into graphical form fields as values instead of remaining as
   placeholders.

## Root Cause

`dual_mode_editor_controller.js` — `handleContentLoaded()` has an
early-return path (lines 138–142) for new recipes (no `<script
data-editor-markdown>` tag). This path skips:

- Setting `originalContent` (stays `null`)
- Setting `originalStructure` (stays `null`)
- Any graphical controller initialization

Then `switchTo()` always round-trips through the server regardless of whether
the source editor was modified, producing wrong results in both directions.

## Fix

Three changes in `dual_mode_editor_controller.js`:

### 1. `handleContentLoaded()` — capture baselines for new recipes

In the early-return path (no `data-editor-markdown` script), capture:
- `originalContent` ← plaintext editor content (the template text)
- `originalStructure` ← graphical controller's `toStructure()` (empty form)

### 2. `switchTo()` — skip fetch when source is unmodified

Before making the server round-trip, check `isModified()` on the source
editor against its original. If unmodified, set the target editor to the
stored original directly:

- Graphical unmodified → set plaintext to `originalContent` (template)
- Plaintext unmodified → load `originalStructure` into graphical (empty form)

If the user HAS made changes, the existing fetch-based conversion runs
normally. This handles both new and edit recipes correctly.

### 3. `handleReset()` — reset graphical form on cancel

Currently only resets plaintext content. Also reset the graphical form to
`originalStructure` when available. New recipe dialogs don't reload via Turbo
Frame, so the graphical form would otherwise retain stale state across
open/cancel cycles.

## Scope

- **One file changed:** `app/javascript/controllers/dual_mode_editor_controller.js`
- **No HTML changes** — the existing template/placeholder setup is correct
- **No new concepts** — leverages existing `originalContent`/`originalStructure`
  tracking and `isModified()` methods already on both child controllers
