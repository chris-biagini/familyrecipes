# Editor Default Focus: Always Focus Close Button

**Issue:** GH #342
**Date:** 2026-04-04

## Problem

When editors open and auto-focus a text input or textarea, iOS Safari zooms
into that field, disorienting the user. The current `focusDefault()` logic
checks for an `[autofocus]` attribute first, falling back to the close button
only when none is found.

## Design

Make the close button the universal default focus target for all editor
dialogs. Remove the `[autofocus]` query from `focusDefault()` so it always
focuses the close button target. Remove all `autofocus` attributes from
editor-related views.

## Changes

1. **`editor_controller.js`** — simplify `focusDefault()` to always focus
   close button (remove `[autofocus]` query).
2. **`homepage/show.html.erb`** — remove `autofocus` from category input,
   tag input, AI import textarea.
3. **`groceries/show.html.erb`** — remove `autofocus` from aisle input.
4. **`menu/show.html.erb`** — remove `autofocus` from dinner picker button.
