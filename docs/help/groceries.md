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

## The Three Sections

Each aisle is split into three sections:

- **Inventory Check** — items the system is asking about. These are either
  new ingredients the system hasn't seen before, or items it thinks you might
  be running low on. Look in your kitchen: tap **Have It** if you have it, or
  **Need It** if you're out. "Need It" moves the item down to To Buy so you
  can pick it up on your next shopping trip. When there are many items to
  verify, an **All Stocked** button confirms everything at once. Items are
  sorted by how many of your selected recipes use them, so the most important
  ones appear first.

- **To Buy** — items you need to purchase, grouped by aisle. These are things
  you've told the system you're out of. Check them off as you buy them.

- **On Hand** — items you have, shown with reduced opacity that fades as the
  item ages. Items you just bought appear bolder so you can confirm your cart
  at a glance. If you run out of something, uncheck it — it moves to To Buy.

## Before You Shop

Walk through your kitchen and work through the **Inventory Check** items.
Tap **Have It** for things you still have, and **Need It** for things you're
out of. Then head to the store and work through **To Buy**, checking items off
as they go in the cart.

You don't have to clear every Inventory Check item before shopping — anything
you skip stays there until next time.

## While Shopping

Check off items as they go in the cart. Checked items get a brief
strikethrough before sliding into the On Hand section, where they appear bold
to confirm what you've just grabbed. If you checked something by mistake,
just uncheck it — same-day corrections are treated as an undo.

Older on-hand items gradually fade, giving you a sense of pantry freshness at
a glance without adding clutter.

## How the System Learns Your Pantry

The system learns how often you need each ingredient by paying attention to
two things: how you answer Inventory Check questions, and when you tell it
you've run out.

When a new ingredient first appears, the system asks about it again in about
a week. Each time you confirm you still have it (**Have It**), the system
waits longer before asking again — and items you consistently keep gradually
build confidence, so the wait grows over time. Items you always have
eventually stop appearing for months at a stretch (except for an occasional
check).

If you check something off by mistake, just uncheck it — the system treats
same-day corrections as an undo, not as running out.

When you tell the system you're out — either by tapping **Need It** in an
Inventory Check, or by unchecking an On Hand item — the system adjusts the
schedule based on how long you actually had the item. If you ran out sooner
than expected, the system loses some confidence and asks sooner next time.

**What this looks like in practice:**

- **First week or two**: the Inventory Check list is long — the system
  doesn't know your kitchen yet. As you tell it what you have and what you
  need, it starts building a picture.
- **After a while**: Inventory Check starts doing the work. Staples like oil,
  salt, and pepper show up there less and less often. To Buy is mostly things
  you actually need.
- **Once it's learned your kitchen**: To Buy is short — just new ingredients
  for this week's recipes and things you've run out of. Inventory Check is an
  occasional quick scan. The list practically runs itself.

## What Happens When Recipes Change

When you deselect a recipe, its ingredients may no longer be needed by any
selected recipe. When that happens, the ingredient is **pruned** — set aside
so you'll re-verify it when it next appears on the list.

Pruning **preserves the learned schedule**. If you confirmed flour every week
for two months and it reached a long schedule, briefly deselecting the recipe
that uses it won't destroy that history. When you re-select the recipe, flour
shows up in Inventory Check — and if you still have it, the schedule resumes
from where it left off.

Telling the system you've run out is different from pruning. Pruning means
"no recipe needs this right now." Running out means "I used it up" — and the
system uses that information to recalibrate.

## Custom Items

Custom items (things you add manually) are not affected by the schedule system
or by pruning. They stay in whatever state you put them in — To Buy or On
Hand — until you remove them. They're meant for one-off purchases and
non-recipe items. They don't appear in Inventory Check.
