---
layout: page
title: Cross-References
section: recipes
prev: /recipes/scaling/
next: /recipes/tags-and-categories/
---

# Cross-References

Cross-references let recipes share steps or link to each other. They're
useful when one recipe is a component of another.

## Embedding a recipe

To pull another recipe's steps inline, use `> @[Recipe Title]` on its own
line inside a step:

~~~
## Make the sauce.

> @[Simple Tomato Sauce]

## Cook the pasta.

- Spaghetti, 400 g
~~~

When the recipe is rendered, the referenced recipe's steps are embedded
exactly as if they were written inline. Grocery quantities from embedded
steps are included in the shopping list.

## Linking to a recipe

To insert a clickable link without embedding, use `@[Recipe Title]` in
normal prose — in step text or in the footer:

~~~
This pairs well with @[Simple Salad].
~~~

This renders as a link to that recipe. No steps are pulled in.

## If the referenced recipe is deleted

A broken reference appears with a notice in place of the embedded steps.
The recipe still works otherwise. Fix it by updating the recipe text to
remove or correct the reference.

## Recipe titles must match exactly

The title in `@[...]` must match the referenced recipe's title exactly,
including capitalization. If a recipe is renamed, update any cross-references
that point to it.
