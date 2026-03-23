/**
 * Client-side fuzzy matching for ingredient autocomplete in the search overlay.
 * Matches against a combined corpus of recipe ingredients, on-hand items, and
 * custom items. Ranking: exact > prefix > substring, with shorter names first
 * among ties. Returns original-case names for display.
 *
 * Collaborators:
 *   - search_overlay_controller.js (sole consumer)
 *   - SearchDataHelper (provides the corpus via JSON blob)
 */

export function matchIngredients(query, ingredients, { max = 10, customItems = [] } = {}) {
  if (!query) return []

  const q = query.toLowerCase()
  const allNames = [...ingredients, ...customItems.map(c => c.name)]
  const scored = []

  for (const name of allNames) {
    const lower = name.toLowerCase()
    if (lower === q) {
      scored.push({ name, score: 0, len: name.length })
    } else if (lower.startsWith(q)) {
      scored.push({ name, score: 1, len: name.length })
    } else if (lower.includes(q)) {
      scored.push({ name, score: 2, len: name.length })
    }
  }

  scored.sort((a, b) => a.score - b.score || a.len - b.len || a.name.localeCompare(b.name))

  const seen = new Set()
  const results = []
  for (const { name } of scored) {
    const key = name.toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    results.push(name)
    if (results.length >= max) break
  }

  return results
}
