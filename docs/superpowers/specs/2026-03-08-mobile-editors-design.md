# Mobile Editor Responsiveness — Design

**Issue:** #201 — editors don't play nice on mobile

## Problems

1. Textarea has no `overflow-wrap`, causing horizontal scroll on long lines
2. 1.5rem padding + 0.85rem monospace wastes horizontal space on small screens
3. Nutrition editor rows (nutrient, portion, form) overflow on ~375px screens
4. Aisle/category editor buttons (1.75rem / 28px) are below 44px touch target minimum
5. Dialog lacks `overflow-x: hidden` to prevent horizontal scroll escape

## Solution

Pure CSS additions in a `@media (max-width: 720px)` block. No JS or layout changes.

1. **Prevent horizontal scroll** — `overflow-wrap: break-word` on textarea, `overflow-x: hidden` on dialog
2. **Tighten padding** — textarea/overlay padding 1.5rem → 0.75rem
3. **Reduce monospace size** — 0.85rem → 0.8rem for more characters per line
4. **Stack nutrition rows** — label above input on narrow screens via flex-wrap
5. **Enlarge tap targets** — aisle buttons 1.75rem → 2.5rem, increase row padding
6. **Reduce min-height** — 60vh → auto on `.hl-wrap`/`.editor-textarea` so dialog flexes within 100vh
