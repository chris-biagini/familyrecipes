// Tiered recipe matching for the search overlay.
//
// Scores a recipe against search tokens using AND logic — every token must
// match somewhere. Returns the best (lowest) tier across all tokens.
// Tier 0 = title, 1 = description, 2 = category, 3 = tag, 4 = ingredient,
// 5 = no match (recipe excluded).
//
// Collaborators:
//   - search_overlay_controller.js (sole consumer)

function tokenTier(recipe, token) {
  if (recipe._title.includes(token)) return 0
  if (recipe._description.includes(token)) return 1
  if (recipe._category.includes(token)) return 2
  if (recipe._tags?.some(t => t.includes(token))) return 3
  if (recipe._ingredients.some(i => i.includes(token))) return 4
  return 5
}

export function matchTier(recipe, tokens) {
  if (tokens.length === 0) return 0

  let best = 5
  for (const token of tokens) {
    const tier = tokenTier(recipe, token)
    if (tier === 5) return 5
    if (tier < best) best = tier
  }
  return best
}
