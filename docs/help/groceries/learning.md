---
layout: page
title: How the System Learns
section: groceries
prev: /groceries/three-sections/
next: /groceries/custom-items/
---

# How the System Learns Your Pantry

The app learns how often you need each ingredient by paying attention to two
things: how you answer Inventory Check questions, and when you tell it you've
run out.

## Building confidence

When a new ingredient first appears, the app asks about it again in about a
week. Each time you confirm you still have it (**Have It**), the app waits
longer before asking again. Items you consistently keep gradually build
confidence, and the wait grows over time. Items you always have eventually
stop appearing for months at a stretch (except for an occasional check).

## What this looks like in practice

- **First week or two**: the Inventory Check list is long — the app doesn't
  know your kitchen yet. As you tell it what you have and what you need, it
  starts building a picture.
- **After a while**: Inventory Check starts doing the work. Staples like oil,
  salt, and pepper show up there less and less often. To Buy is mostly things
  you actually need.
- **Once it's learned your kitchen**: To Buy is short — just new ingredients
  for this week's recipes and things you've run out of. Inventory Check is
  an occasional quick scan.

## When you run out

Telling the app you're out — either by tapping **Need It** in Inventory
Check, or by using the **Need It** button on an On Hand item — adjusts the
schedule based on how long you actually had the item. If you ran out sooner
than expected, the app loses some confidence and asks sooner next time.

## Pruning

When you deselect a recipe, its ingredients may no longer be needed by any
selected recipe. When that happens, the ingredient is *pruned* — set aside
so you'll re-verify it when it next appears on the list.

Pruning **preserves the learned schedule**. If you confirmed flour every week
for two months, briefly deselecting the recipe that uses it won't destroy
that history. When you re-select the recipe, flour shows up in Inventory
Check — and if you still have it, the schedule resumes from where it left off.

Telling the app you've run out is different from pruning. Pruning means
"no recipe needs this right now." Running out means "I used it up" — and
the app uses that information to recalibrate.
