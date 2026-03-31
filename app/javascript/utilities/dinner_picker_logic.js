/**
 * Pure computation functions for the dinner picker: recency-weighted selection
 * with decline penalties. Extracted from the controller for testability.
 *
 * - dinner_picker_controller.js: consumes these functions
 * - test/javascript/dinner_picker_test.mjs: unit tests
 */

const DECLINE_FACTOR = 0.3

export function computeFinalWeights(recipes, recencyWeights, declines) {
  const weights = {}
  for (const recipe of recipes) {
    const base = recencyWeights[recipe.slug] ?? 1.0
    const declineCount = declines[recipe.slug] ?? 0
    weights[recipe.slug] = base * (DECLINE_FACTOR ** declineCount)
  }
  return weights
}

export function weightedRandomPick(weights) {
  const entries = Object.entries(weights)
  if (entries.length === 0) return null

  const total = entries.reduce((sum, [, w]) => sum + w, 0)
  if (total === 0) return entries[0][0]

  let roll = Math.random() * total
  for (const [slug, w] of entries) {
    roll -= w
    if (roll <= 0) return slug
  }
  return entries[entries.length - 1][0]
}
