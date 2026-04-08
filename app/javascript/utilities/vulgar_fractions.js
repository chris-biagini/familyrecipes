/**
 * Client-side mirror of FamilyRecipes::VulgarFractions. Formats decimals as
 * Unicode fraction glyphs (0.5 → "½") for scaled ingredient display. When a
 * metric unit (g, kg, ml, l) is passed, skips vulgar fractions and returns
 * plain decimals instead. Also determines singular/plural noun agreement for
 * fractional quantities (½ is singular: "½ cup", not "½ cups"). Used by
 * recipe_state_controller.
 */
const VULGAR_FRACTIONS = [
  [1/2, '\u00BD'], [1/3, '\u2153'], [2/3, '\u2154'],
  [1/4, '\u00BC'], [3/4, '\u00BE'],
  [1/5, '\u2155'], [2/5, '\u2156'], [3/5, '\u2157'], [4/5, '\u2158'],
  [1/6, '\u2159'], [5/6, '\u215A'],
  [1/8, '\u215B'], [3/8, '\u215C'], [5/8, '\u215D'], [7/8, '\u215E']
]

const FRACTION_STRINGS = [
  [1/2, '1/2'], [1/3, '1/3'], [2/3, '2/3'],
  [1/4, '1/4'], [3/4, '3/4'],
  [1/5, '1/5'], [2/5, '2/5'], [3/5, '3/5'], [4/5, '4/5'],
  [1/6, '1/6'], [5/6, '5/6'],
  [1/8, '1/8'], [3/8, '3/8'], [5/8, '5/8'], [7/8, '7/8']
]

const METRIC_UNITS = new Set(['g', 'kg', 'ml', 'l'])

export function formatVulgar(value, unit = null) {
  if (unit && METRIC_UNITS.has(unit.toLowerCase())) {
    if (Number.isInteger(value)) return String(value)
    const rounded = Math.round(value * 100) / 100
    return String(rounded)
  }
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

export function toFractionString(value) {
  if (Number.isInteger(value) || Math.abs(value - Math.round(value)) < 0.001) {
    return String(Math.round(value))
  }
  const intPart = Math.floor(value)
  const fracPart = value - intPart
  const match = FRACTION_STRINGS.find(([v]) => Math.abs(fracPart - v) < 0.001)
  if (match) return intPart === 0 ? match[1] : `${intPart} ${match[1]}`
  const rounded = Math.round(value * 100) / 100
  return String(rounded)
}
