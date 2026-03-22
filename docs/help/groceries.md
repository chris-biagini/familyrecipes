# Groceries

The groceries page builds a shopping list from the recipes and quick bites you
select on the menu page. 

## How the Shopping List Works

Every ingredient from your selected recipes and quick bites appears on the
list, grouped by aisle. Quantities from multiple recipes are combined — if
two recipes call for onions, you see one entry with the total amount.

You can also add **custom items** (things not tied to any recipe) using the
input at the bottom of the page. Type a name, or use `Name @ Aisle` to place
an item in a specific aisle.

## Taking Inventory 

Items are either **To Buy** (unchecked) or **On Hand** (checked, in a
collapsed section at the bottom of each aisle).

Before you go shopping, look around your kitchen. If an item is marked **On
Hand** but you've run out of it, uncheck it. If an item is marked **To Buy**
but you have enough for now, check it off. 

## Staying Visible While Shopping

When you check an item off during a shopping trip, it stays visible in the
main list (with a strikethrough) rather than immediately disappearing into the
On Hand section. This makes it easy to spot and undo a mistake — if you
realize you checked off milk but don't actually have it, just uncheck it.

Checked items settle into the On Hand section the next time you visit the
groceries page (e.g., after navigating to the menu or reopening the app).

## How the System Learns Your Pantry

Over time, the groceries page learns how often you tend to buy each
ingredient. At first, it will move each **On Hand** item back to **To Buy**
after one week has passed. But every time you confirm that you have something
(by checking it off), the system grows a little more confident that you keep
it stocked and waits longer before asking again.

**Here's how it works:**

The first time you check off an ingredient, the system asks again in about a
week. Each time you confirm it again, the system waits a bit longer — and
items you consistently have on hand build confidence quickly, so the wait
grows faster over time. Items you always have eventually stop appearing on the
list altogether (except for an occasional check every few months).

The system adapts to your actual pantry, not a set of rules you have to
configure. Over time, each ingredient settles into its own rhythm that matches
your real usage.

**What this looks like in practice:**

- **First few weeks**: the list is long — everything needs checking (the
  system doesn't know your kitchen yet).
- **After a while**: the list is shorter — staples like oil, salt, and pepper
  aren't due for verification yet.
- **Once it's learned your kitchen**: the list is mostly just new ingredients
  from this week's recipes, plus the occasional staple that's due for a check.

The system adapts to any shopping frequency, but it converges faster if you
shop regularly — the more often you confirm items, the quicker it learns what
you keep stocked.

You don't need to do anything to make this work. Just check and uncheck items
honestly, and the system tunes itself.

Even high-confidence items eventually reappear for a check. When an
ingredient's schedule expires, it shows up on the To Buy list again — not
because anything went wrong, but because the system wants to verify you still
have it. Just check it off and the cycle continues.

## What Happens When Recipes Change

When you deselect a recipe, its ingredients may no longer be needed by any
selected recipe. When that happens, the ingredient is **pruned** — moved back
to To Buy so you'll re-verify it when it next appears on the list.

Unlike unchecking (which resets the schedule), pruning **preserves the learned
interval**. If you confirmed flour every week for two months and it reached an
eight-week schedule, briefly deselecting the recipe that uses it won't destroy
that history. When you re-select the recipe, flour shows up as To Buy — but
once you confirm it, the schedule resumes from where it left off rather than
starting from scratch. (Your confirmation also advances it to the next level,
just like any other confirmation.)

Unchecking is different: when you tell the system "I don't have this," it
adjusts the schedule based on how long you actually had the item. If you ran
out sooner than expected, the system loses some confidence and asks sooner
next time.

Ingredients that appear in many of your recipes (like olive oil) are rarely
pruned, because there's almost always a selected recipe that needs them. Rare
ingredients (like fresh basil) are pruned frequently. This means the system
naturally asks about rare ingredients more often and staples less often — even
before the confidence system kicks in.

## Custom Items

Custom items (things you add manually) are not affected by the confidence
system or by pruning. They stay in whatever state you put them in — checked
or unchecked — until you remove them. They're meant for one-off purchases
and non-recipe items.
