---
layout: page
title: Cooking Mode
section: recipes
prev: /recipes/editing/
next: /recipes/scaling/
---

# Cooking Mode

While cooking, you can cross off steps and ingredients to track your progress.

## Crossing off steps

Click the `##` step heading to strike through the entire step — ingredients,
instructions, and all. Click it again to uncheck.

## Crossing off ingredients

Click any ingredient line to strike it through individually. Useful when a
step has several ingredients and you want to check them off as you add them.

## Your progress is saved

Checked state is stored in your browser (localStorage) and persists across
page loads and app updates. If you refresh the page or come back later, your
checkmarks will still be there.

The state is per-recipe and per-device — it's not shared with other household
members or synced across devices.

## Screen stays on

The app requests a wake lock while you're viewing a recipe, so your screen
won't dim while you're in the middle of a step. The same applies on the
[Groceries]({{ site.baseurl }}/groceries/how-it-works/) page.

Wake lock requires a supported browser (most modern mobile browsers) and
won't activate on desktop. If the browser doesn't support it, recipes still
work normally — the screen may just auto-dim after inactivity.
