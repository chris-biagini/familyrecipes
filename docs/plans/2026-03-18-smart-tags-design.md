# Smart Tags Design

**GH Issue:** #252
**Date:** 2026-03-18

## Overview

Curated tags get distinctive visual treatment: colored pills with emoji
prefixes via CSS `::before`. A Kitchen-level toggle (`decorate_tags`) lets
users revert to neutral pills. Tags not in the curated registry render with
the existing neutral styling.

## Decisions

- **Emoji rendering:** CSS `::before` pseudo-element — keeps tag names clean in
  the data layer, decoration is purely presentational.
- **Composition:** Tags with `style: :crossout` get a bold red ✕ overlay
  (CSS `::after`) — used for "-free" restriction tags. No circle background,
  just the ✕ character with a text-shadow halo for contrast. Stack/badge
  compositions deferred.
- **Color palette:** Five semantic color groups, each with light and dark mode
  variants. Emoji prefixes do the primary distinguishing work (important for
  CVD accessibility — color is supplementary, not the sole differentiator).
  - **Green** — plant-based dietary (vegetarian, vegan)
  - **Amber** — dietary restrictions (gluten-free, kosher, halal, etc.)
  - **Blue** — effort/style (weeknight, easy, one-pot, etc.)
  - **Purple** — attribution/special (julia-child, holiday, comfort-food, etc.)
  - **Cuisine (terracotta)** — all cuisines share one color; flag emoji provide
    per-country identity
- **Registry location:** `FamilyRecipes::SmartTagRegistry` in
  `lib/familyrecipes/smart_tag_registry.rb` — a frozen constant, not
  user-configurable. Curated and opinionated.
- **Settings toggle:** `decorate_tags` boolean on Kitchen, checkbox in the
  Recipes section of the settings dialog. Default `true`. When off, all tags
  render as current neutral pills.

## Data Model

### SmartTagRegistry

`lib/familyrecipes/smart_tag_registry.rb` — a module under the `FamilyRecipes`
namespace containing a `TAGS` frozen hash.

```ruby
module FamilyRecipes
  module SmartTagRegistry
    TAGS = {
      # Green — plant-based dietary
      "vegetarian" => { emoji: "🌿", color: :green },
      "vegan"      => { emoji: "🌱", color: :green },

      # Amber — dietary restrictions
      "gluten-free" => { emoji: "🌾", color: :amber, style: :crossout },
      "grain-free"  => { emoji: "🌾", color: :amber, style: :crossout },
      "dairy-free"  => { emoji: "🥛", color: :amber, style: :crossout },
      "nut-free"    => { emoji: "🥜", color: :amber, style: :crossout },
      "egg-free"    => { emoji: "🥚", color: :amber, style: :crossout },
      "soy-free"    => { emoji: "🫘", color: :amber, style: :crossout },
      "kosher"      => { emoji: "✡️",  color: :amber },
      "halal"       => { emoji: "☪️",  color: :amber },

      # Blue — effort/style
      "weeknight"  => { emoji: "⏱️", color: :blue },
      "easy"       => { emoji: "👌", color: :blue },
      "quick"      => { emoji: "⚡", color: :blue },
      "one-pot"    => { emoji: "🍳", color: :blue },
      "make-ahead" => { emoji: "📦", color: :blue },

      # Purple — attribution/special
      "julia-child"  => { emoji: "👩‍🍳", color: :purple },
      "kenji"        => { emoji: "🔬", color: :purple },
      "grandma"      => { emoji: "💛", color: :purple },
      "holiday"      => { emoji: "🎉", color: :purple },
      "comfort-food" => { emoji: "🛋️", color: :purple },

      # Cuisine — flag emoji, shared terracotta color
      "american"  => { emoji: "🇺🇸", color: :cuisine },
      "french"    => { emoji: "🇫🇷", color: :cuisine },
      "thai"      => { emoji: "🇹🇭", color: :cuisine },
      "italian"   => { emoji: "🇮🇹", color: :cuisine },
      "mexican"   => { emoji: "🇲🇽", color: :cuisine },
      "japanese"  => { emoji: "🇯🇵", color: :cuisine },
      "indian"    => { emoji: "🇮🇳", color: :cuisine },
      "chinese"   => { emoji: "🇨🇳", color: :cuisine },
      "korean"    => { emoji: "🇰🇷", color: :cuisine },
      "greek"     => { emoji: "🇬🇷", color: :cuisine },
      "ethiopian" => { emoji: "🇪🇹", color: :cuisine },
      "lebanese"  => { emoji: "🇱🇧", color: :cuisine },
    }.freeze

    def self.lookup(tag_name)
      TAGS[tag_name]
    end
  end
end
```

Emoji choices are provisional — a dedicated emoji curation session is planned
during implementation.

### Migration

Add `decorate_tags` boolean to `kitchens`:

```ruby
add_column :kitchens, :decorate_tags, :boolean, default: true, null: false
```

## Rendering

### Helper

A `SmartTagHelper` (or method in `GroceriesHelper` / `ApplicationHelper`)
provides the bridge between the registry and views:

```ruby
def smart_tag_pill_attrs(tag_name, kitchen: current_kitchen)
  return {} unless kitchen.decorate_tags

  entry = FamilyRecipes::SmartTagRegistry.lookup(tag_name)
  return {} unless entry

  classes = ["tag-pill--#{entry[:color]}"]
  classes << "tag-pill--crossout" if entry[:style] == :crossout

  { class: classes, data: { smart_emoji: entry[:emoji] } }
end
```

The helper returns CSS classes and a `data-smart-emoji` attribute. The
`::before` pseudo-element reads the emoji from the data attribute via
`attr()` — or, since `attr()` for `content` beyond strings has limited
support, the emoji is set directly as `content` in per-tag CSS rules generated
from the registry.

**Implementation note:** Since CSS `content: attr(data-smart-emoji)` works
for string values in `::before`, this is the cleanest approach — one CSS rule
for all smart tags rather than per-tag rules.

### Touch Points

Four places render tag pills:

1. **Recipe content** (`_recipe_content.html.erb`) — server-rendered pills.
   Apply `smart_tag_pill_attrs` to each tag's button element.

2. **Search overlay** (`search_overlay_controller.js`) — client-rendered pills.
   Needs a JS-accessible copy of the registry. Embed via a helper (same
   pattern as `SearchDataHelper` embedding recipe data). The controller reads
   the registry when building pill DOM and applies classes + `data-smart-emoji`.

3. **Tag input** (`tag_input_controller.js`) — editor pills and autocomplete.
   Same JS registry lookup. Apply smart styling to pills in the tag input and
   optionally show emoji in autocomplete dropdown items.

4. **Homepage tag management dialog** — admin view, keep neutral pills. No
   changes needed.

### JS Registry Access

Embed the registry as a JSON blob in the layout (or search overlay partial),
gated on `decorate_tags`:

```erb
<% if current_kitchen.decorate_tags %>
  <script type="application/json" data-smart-tags>
    <%= FamilyRecipes::SmartTagRegistry::TAGS.to_json.html_safe %>
  </script>
<% end %>
```

JS controllers read this on connect. When absent (decorations off), they
render neutral pills.

## CSS

### Custom Properties

```css
/* Smart tag color groups — light mode */
--smart-green-bg: #d4edda;    --smart-green-text: #1b5e20;
--smart-amber-bg: #fff3cd;    --smart-amber-text: #7a5d00;
--smart-blue-bg: #d6eaf8;     --smart-blue-text: #1a4a6e;
--smart-purple-bg: #e8daf5;   --smart-purple-text: #4a2080;
--smart-cuisine-bg: #f5ddd0;  --smart-cuisine-text: #6e3a22;

/* Dark mode overrides */
--smart-green-bg: #1a3a1e;    --smart-green-text: #a8d8a0;
--smart-amber-bg: #3a3018;    --smart-amber-text: #d8c070;
--smart-blue-bg: #1a2e3e;     --smart-blue-text: #90c0e0;
--smart-purple-bg: #2a1e3a;   --smart-purple-text: #c0a8e0;
--smart-cuisine-bg: #3a2820;  --smart-cuisine-text: #d8b0a0;
```

### Classes

```css
.tag-pill--green   { background: var(--smart-green-bg);   color: var(--smart-green-text); }
.tag-pill--amber   { background: var(--smart-amber-bg);   color: var(--smart-amber-text); }
.tag-pill--blue    { background: var(--smart-blue-bg);     color: var(--smart-blue-text); }
.tag-pill--purple  { background: var(--smart-purple-bg);   color: var(--smart-purple-text); }
.tag-pill--cuisine { background: var(--smart-cuisine-bg); color: var(--smart-cuisine-text); }

/* Emoji prefix via data attribute */
.tag-pill[data-smart-emoji]::before {
  content: attr(data-smart-emoji);
  margin-right: 0.3em;
  font-size: 0.85em;
}

/* Crossout ✕ overlay */
.tag-pill--crossout::after {
  content: "✕";
  position: absolute;
  bottom: -0.15em;
  right: -0.3em;
  font-size: 0.7em;
  font-weight: 900;
  color: #c44;
  line-height: 1;
  text-shadow:
    -1px -1px 0 var(--smart-amber-bg),
     1px -1px 0 var(--smart-amber-bg),
    -1px  1px 0 var(--smart-amber-bg),
     1px  1px 0 var(--smart-amber-bg);
}
```

The crossout text-shadow uses the pill's own background color for the halo,
ensuring contrast in both light and dark modes. The `.tag-pill--crossout`
elements need `position: relative` on the pill.

## Settings

- Add checkbox to the Recipes section of `_dialog.html.erb`
- Label: "Decorate special tags" (with sublabel: "Show emoji and colors for
  dietary, cuisine, and other recognized tags")
- Wire through `SettingsController` permitted params
- `Kitchen#broadcast_update` on save handles live refresh

## Testing

- **Unit:** `SmartTagRegistry.lookup` returns correct entries, returns nil for
  unknown tags
- **Helper:** `smart_tag_pill_attrs` returns correct classes/data when
  decorations enabled, empty hash when disabled
- **Integration:** Recipe page renders smart-styled pills when enabled, neutral
  when disabled
- **Settings:** Toggle persists and affects rendering
- **Search overlay:** Smart tag data embedded in page when enabled, absent when
  disabled
