# On Hand: Replace Non-Today Checkboxes with "Need It" Button

**Issue:** [#291](https://github.com/chris-biagini/familyrecipes/issues/291)
**Date:** 2026-03-24

## Problem

On Hand items all render with pre-checked checkboxes regardless of when they
were confirmed. This creates a UX mismatch: unchecking something you bought
last week doesn't feel right — you didn't "un-buy" it, you ran out. The bold
styling on "confirmed today" items is the only visual distinction, and it's
subtle.

## Design

Split On Hand items into two visual treatments based on `confirmed_at`:

| Condition | UI | Action on click |
|---|---|---|
| `confirmed_at == today` | Checkbox (pre-checked) | `uncheck!` (existing behavior) |
| `confirmed_at != today` | "Need It" button | `need_it!` (SM-2 blending) |

### What changes

1. **Remove bold styling** from `.confirmed-today`. Today items are now
   distinguished by having checkboxes; non-today items have a "Need It" button.

2. **View split** in `_shopping_list.html.erb`: the on-hand `<li>` renders
   either a checkbox or a "Need It" button based on `confirmed_today?`.

3. **"Need It" button fires `need_it` action**, not `uncheck`. This is a
   behavioral improvement: `need_it!` performs SM-2 interval blending
   (records observed consumption period), while `uncheck!` is a simpler
   revert. For items on hand for days/weeks, blending is more accurate.

4. **JS handler** in `grocery_ui_controller.js`: "Need It" buttons in on-hand
   use the same `data-grocery-action="need-it"` as Inventory Check buttons.
   The existing `sendAction` dispatcher already handles this — no new JS
   needed.

5. **CSS**: delete `.confirmed-today` bold rule. The `.on-hand-fresh/mid/aging`
   opacity classes remain unchanged for non-today items.

### What stays the same

- Three-zone model (Inventory Check / To Buy / On Hand) — unchanged.
- Today items keep checkbox + `uncheck!` behavior — if you just bought
  something and realize you didn't, unchecking is the right semantic.
- On Hand section headers, collapse behavior, freshness opacity — all unchanged.
- Inventory Check zone — unchanged.
- To Buy zone — unchanged.

### Markup sketch

Non-today on-hand item (new):
```erb
<li class="<%= freshness_class %>" data-item="<%= item[:name] %>">
  <button class="btn btn-sm btn-need-it" data-grocery-action="need-it"
          data-item="<%= item[:name] %>">Need It</button>
  <span class="item-text"><%= item[:name] %> <span class="item-amount">...</span></span>
</li>
```

Today on-hand item (unchanged except no bold):
```erb
<li data-item="<%= item[:name] %>">
  <label class="check-off">
    <input class="custom-checkbox" type="checkbox" data-item="<%= item[:name] %>" checked>
    <span class="item-text">...</span>
  </label>
</li>
```

### Animation

Non-today "Need It" clicks should use the same exit animation as IC buttons
(immediate `<li>` removal). The item reappears in To Buy after the Turbo
morph broadcast.

### Print

No change needed — print CSS already hides on-hand sections entirely.

## Files touched

| File | Change |
|---|---|
| `app/views/groceries/_shopping_list.html.erb` | Split on-hand rendering by `confirmed_today?` |
| `app/assets/stylesheets/groceries.css` | Delete `.confirmed-today` rule; add layout for button-style on-hand items |
| `app/helpers/groceries_helper.rb` | No change — `confirmed_today?` already exists |
| `app/javascript/controllers/grocery_ui_controller.js` | No change — `need-it` action already handled |
| `test/helpers/groceries_helper_test.rb` | Verify existing `confirmed_today?` coverage |
| `test/controllers/groceries_controller_test.rb` | Add test for need_it on on-hand item |

## Out of scope

- Visual freshness indicators beyond existing opacity (future consideration)
- Changes to Inventory Check or To Buy zones
- SM-2 algorithm changes
