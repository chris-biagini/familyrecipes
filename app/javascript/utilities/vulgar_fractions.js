/**
 * Client-side mirror of FamilyRecipes::VulgarFractions. Formats decimals as
 * Unicode fraction glyphs (0.5 → "½") for scaled ingredient display. Also
 * determines singular/plural noun agreement for fractional quantities (½ is
 * singular: "½ cup", not "½ cups"). Used by recipe_state_controller.
 */
const VULGAR_FRACTIONS = [
  [1/2, '\u00BD'], [1/3, '\u2153'], [2/3, '\u2154'],
  [1/4, '\u00BC'], [3/4, '\u00BE'],
  [1/8, '\u215B'], [3/8, '\u215C'], [5/8, '\u215D'], [7/8, '\u215E']
]

export function formatVulgar(value) {
  if (Number.isInteger(value)) return String(value)
  const intPart = Math.floor(value)
  const fracPart = value - intPart
  const match = VULGAR_FRACTIONS.find(([v]) => Math.abs(fracPart - v) < 0.001)
  if (match) return intPart === 0 ? match[1] : `${intPart}${match[1]}`
  const rounded = Math.round(value * 100) / 100
  return String(rounded)
}

export function isVulgarSingular(value) {
  if (Math.abs(value - 1) < 0.001) return true
  if (value <= 0 || value >= 1) return false
  return VULGAR_FRACTIONS.some(([v]) => Math.abs(value - v) < 0.001)
}
