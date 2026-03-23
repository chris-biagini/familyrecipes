# On-Hand Visual Treatment Redesign

## Problem

On-hand items on the grocery page use strikethrough + 40% opacity + a checked
checkbox. This reads as "completed task" — but on-hand items are stocked
inventory, not finished work. The visual treatment conflates "just tossed in
the cart" with "been in the pantry for two weeks."

## Design

Replace the strikethrough with an opacity-based freshness gradient. The filled
red checkbox already distinguishes on-hand (checked) from to-buy (unchecked) —
strikethrough is redundant and misleading.

### Visual states

| State | Condition | Opacity | Weight | CSS class |
|-------|-----------|---------|--------|-----------|
| Just bought | `confirmed_at == today` | 1.0 | bold (600) | `.confirmed-today` (existing) |
| Fresh | 0–33% through interval | 0.75 | normal | `.on-hand-fresh` |
| Mid | 33–66% through interval | 0.625 | normal | `.on-hand-mid` |
| Aging | 66–100% through interval | 0.50 | normal | `.on-hand-aging` |

Progress formula:

```
effective = (interval * SAFETY_MARGIN).to_i   # integer days, matches entry_on_hand?
days_elapsed = today - confirmed_at
progress = days_elapsed.to_f / effective
```

The `.to_i` truncation matches `MealPlan#entry_on_hand?`, so items hit the
aging bin just before they'd expire into inventory check. Boundary semantics:
`progress < 0.33` → fresh, `progress < 0.66` → mid, else aging. Clamped —
progress values above 1.0 (shouldn't happen for on-hand items, but defensively)
map to `:aging`.

Custom items (nil interval) get `.on-hand-fresh` since they have no expiry.

### Consistency with existing patterns

- **Menu page** already uses opacity as a proxy for how many on-hand
  ingredients a recipe has. This extends that vocabulary to individual items.
- **Same-day undo** behavior is unchanged. `MealPlan#undo_same_day_check`
  already treats same-day unchecks as corrections, not depletion signals. The
  bold "just bought" state makes this visually intuitive — unchecking a bold
  item clearly feels like an undo.

## Changes

### CSS (`groceries.css`)

The base rule `.check-off input:checked + .item-text` applies to both to-buy
and on-hand items. To-buy items use it for the brief strikethrough flash
before the exit animation collapses them. **Keep the base rule intact.** Add a
scoped override for on-hand items only:

```css
.on-hand-items .check-off input[type="checkbox"]:checked + .item-text {
  text-decoration: none;
  opacity: unset;
}
```

Add three freshness classes on the `<li>`:

```css
.on-hand-fresh  { opacity: 0.75; }
.on-hand-mid    { opacity: 0.625; }
.on-hand-aging  { opacity: 0.50; }
```

The existing `.confirmed-today .item-text { font-weight: 600 }` rule stays
as-is. Confirmed-today items have no freshness class, so they inherit the
default opacity of 1.0.

**Print CSS:** The existing print override that resets strikethrough/opacity on
checked items (lines 383–387) may become partially redundant but is harmless.
Leave it for defensive coverage — it ensures print always renders at full
opacity regardless of freshness classes.

### Helper (`groceries_helper.rb`)

New method `on_hand_freshness_class(entry)` accepts an on-hand entry hash
directly (already looked up by the caller) and returns the CSS class string.
This avoids duplicating the case-insensitive hash lookup that `confirmed_today?`
and `restock_tooltip` already perform.

```
effective = (entry['interval'] * SAFETY_MARGIN).to_i
progress = (today - confirmed_at).to_f / effective
progress < 0.33  → "on-hand-fresh"
progress < 0.66  → "on-hand-mid"
else              → "on-hand-aging"
```

Nil interval → `"on-hand-fresh"`.

### Partial (`_shopping_list.html.erb`)

In the on-hand loop, look up the entry and pass it to `on_hand_freshness_class`
for non-today items. The `<li>` gets either `confirmed-today` or the freshness
class — never both.

### Help doc (`docs/help/groceries.md`)

Update the **On Hand** bullet (lines 32–34) to mention that items fade
gradually as they age. Update the **While Shopping** section (lines 48–53) —
the strikethrough description applies to to-buy items being checked off, which
is unchanged; clarify that on-hand items use opacity instead of strikethrough.

## Test cases

1. Fresh bin — entry at 0% progress (just confirmed yesterday)
2. Mid bin — entry at 50% progress
3. Aging bin — entry at 80% progress
4. Nil interval — returns `on-hand-fresh`
5. Boundary: exactly 0.33 progress → mid (not fresh)
6. Boundary: exactly 0.66 progress → aging (not mid)
7. Edge: progress > 1.0 (defensive) → aging

## Files touched

1. `app/assets/stylesheets/groceries.css` — scoped on-hand override, freshness classes
2. `app/helpers/groceries_helper.rb` — add `on_hand_freshness_class` method
3. `app/views/groceries/_shopping_list.html.erb` — apply freshness class to on-hand `<li>`
4. `docs/help/groceries.md` — update On Hand and While Shopping sections
5. `test/helpers/groceries_helper_test.rb` — freshness bin tests
