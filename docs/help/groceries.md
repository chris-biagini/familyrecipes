# Groceries

The groceries page builds a shopping list from the recipes and quick bites you
select on the menu page, organized by aisle. It also tracks what you have at
home so you only see what you actually need to buy.

## The Weekly Flow

1. **Plan meals** on the menu page — select recipes for the week.
2. **Take inventory** on the groceries page — check off ingredients you already
   have at home.
3. **Go shopping** — buy what's left on the list, checking items off as you
   place them in the cart.

## How the Shopping List Works

Every ingredient from your selected recipes and quick bites appears on the
list, grouped by aisle. Quantities from multiple recipes are combined — if
two recipes call for onions, you see one entry with the total amount.

You can also add **custom items** (things not tied to any recipe) using the
input at the bottom of the page. Type a name, or use `Name @ Aisle` to place
an item in a specific aisle.

## Checking Items Off

Items are either **To Buy** (unchecked, in the main list) or **On Hand**
(checked, in a collapsed section at the bottom of each aisle).

- **At home**: check off ingredients you already have. They move to On Hand.
- **At the store**: check off ingredients as you place them in the cart.
- **Mid-week**: if you run out of something, uncheck it from On Hand to move
  it back to To Buy — even if you're not planning a shopping trip yet. This
  is the fastest way to make sure it lands on the list for next time.

## Staying Visible While Shopping

When you check an item off during a shopping trip, it stays visible in the
main list (with a strikethrough) rather than immediately disappearing into the
On Hand section. This makes it easy to spot and undo a mistake — if you
realize you checked off milk but don't actually have it, just uncheck it.

Checked items settle into the On Hand section the next time you visit the
groceries page (e.g., after navigating to the menu or reopening the app).

## How the System Learns Your Pantry

The groceries page uses a spaced-repetition model (think "Anki for
groceries") to figure out which ingredients you almost always have at home
and which ones you need to check every time.

**Here's how it works:**

Every time you confirm that you have an ingredient (by checking it off), the
system remembers when you confirmed it and schedules the next check further in
the future. The first time you check off salt, the system will ask again in
about a week. Confirm it a second time, and it waits two weeks. Then four.
Then eight. Over time, the system learns that you always have salt and stops
asking about it — unless you tell it otherwise by unchecking salt, which
resets the schedule.

Meanwhile, an ingredient like milk — which you sometimes have and sometimes
don't — keeps its schedule short because you occasionally uncheck it. The
system adapts to your actual pantry, not a set of rules you have to configure.

**What this looks like in practice:**

- **Week 1**: the list is long — everything needs checking (the system doesn't
  know your kitchen yet).
- **Week 3**: the list is shorter — staples like oil, salt, and pepper aren't
  due for verification yet.
- **Week 8**: the list is mostly just new ingredients from this week's recipes,
  plus the occasional staple that's due for a check.

You don't need to do anything to make this work. Just check and uncheck items
honestly, and the system tunes itself.

## What Happens When Recipes Change

When you deselect a recipe, its ingredients may no longer be needed by any
selected recipe. When that happens, the ingredient is **pruned** — removed
from On Hand and its verification schedule is reset.

If you later select a recipe that uses the same ingredient, it reappears in
To Buy as if it were new. This is intentional: if an ingredient fell off the
list long enough to be pruned, there's a decent chance your supply situation
has changed. Better to check once than to assume.

Ingredients that appear in many of your recipes (like olive oil) are rarely
pruned, because there's almost always a selected recipe that needs them. Rare
ingredients (like fresh basil) are pruned frequently. This means the system
naturally asks about rare ingredients more often and staples less often — even
before the spaced-repetition schedule kicks in.

## Custom Items

Custom items (things you add manually) are not affected by the
spaced-repetition system or by pruning. They stay in whatever state you put
them in — checked or unchecked — until you remove them. They're meant for
one-off purchases and non-recipe items.
