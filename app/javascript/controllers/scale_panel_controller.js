import { Controller } from "@hotwired/stimulus"

/**
 * Inline collapsible recipe scaling panel. Renders as a "Scale" link in the
 * recipe-meta line; clicking it expands a strip with preset scale buttons
 * (½×, 1×, 2×, 3×) and a free-form text input. Input supports integers,
 * decimals, and fractions (e.g. "3/2", "372/400"). Presets and input stay
 * in sync — clicking a preset updates the input and vice versa.
 *
 * Dispatches "scale-panel:change" on factor change, consumed by
 * recipe_state_controller for actual ingredient scaling. Syncs from
 * restored state via two mechanisms (async module loading means controller
 * connect order is nondeterministic):
 *   1. "recipe-state:restored" event — if scale-panel connects first
 *   2. data-restored-scale-factor attribute — if recipe-state connects first
 *
 * - recipe_state_controller: consumes change events, sets restored attribute
 */
const PRESETS = [
  { label: '\u00BD\u00D7', value: 0.5, input: '1/2' },
  { label: '1\u00D7', value: 1, input: '1' },
  { label: '2\u00D7', value: 2, input: '2' },
  { label: '3\u00D7', value: 3, input: '3' }
]

export default class extends Controller {
  static targets = ['toggle', 'panel', 'inner', 'input', 'preset', 'reset']

  connect() {
    this.open = false
    this.factor = 1

    this.boundOnRestored = (e) => this.syncToFactor(e.detail.factor)
    this.element.addEventListener('recipe-state:restored', this.boundOnRestored)

    const restored = parseFloat(this.element.dataset.restoredScaleFactor)
    if (restored > 0 && isFinite(restored)) this.syncToFactor(restored)
  }

  disconnect() {
    this.element.removeEventListener('recipe-state:restored', this.boundOnRestored)
  }

  toggle() {
    this.open = !this.open
    this.panelTarget.classList.toggle('open', this.open)
    this.innerTarget.setAttribute('aria-hidden', !this.open)
  }

  selectPreset(e) {
    const idx = this.presetTargets.indexOf(e.currentTarget)
    if (idx === -1) return

    this.updateFactor(PRESETS[idx].value, PRESETS[idx].input)
  }

  onInput() {
    const raw = this.inputTarget.value.trim()
    const factor = this.parseFactor(raw)

    if (!(factor > 0 && isFinite(factor))) {
      this.inputTarget.classList.add('invalid')
      return
    }

    this.inputTarget.classList.remove('invalid')
    this.updateFactor(factor, raw)
  }

  reset() {
    this.updateFactor(1, '1')
  }

  updateFactor(factor, inputText) {
    this.factor = factor
    this.inputTarget.value = inputText
    this.inputTarget.classList.remove('invalid')
    this.highlightPreset(factor)
    this.updateToggleLabel(factor)
    this.updateResetVisibility(factor)

    this.dispatch('change', { detail: { factor }, bubbles: true })
  }

  syncToFactor(factor) {
    this.factor = factor
    const preset = PRESETS.find(p => Math.abs(p.value - factor) < 0.001)
    this.inputTarget.value = preset ? preset.input : String(Math.round(factor * 100) / 100)
    this.inputTarget.classList.remove('invalid')
    this.highlightPreset(factor)
    this.updateToggleLabel(factor)
    this.updateResetVisibility(factor)
  }

  highlightPreset(factor) {
    this.presetTargets.forEach((btn, idx) => {
      btn.classList.toggle('active', Math.abs(PRESETS[idx].value - factor) < 0.001)
    })
  }

  updateToggleLabel(factor) {
    if (!this.hasToggleTarget) return
    if (Math.abs(factor - 1) < 0.001) {
      this.toggleTarget.textContent = 'Scale'
    } else {
      const pretty = Number.isInteger(factor)
        ? factor
        : Math.round(factor * 100) / 100
      this.toggleTarget.textContent = `Scale (\u00D7${pretty})`
    }
  }

  updateResetVisibility(factor) {
    if (!this.hasResetTarget) return
    this.resetTarget.hidden = Math.abs(factor - 1) < 0.001
  }

  parseFactor(str) {
    str = str.trim()
    const frac = str.match(/^(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)$/)
    if (frac) return parseFloat(frac[1]) / parseFloat(frac[2])
    const num = parseFloat(str)
    return isNaN(num) ? NaN : num
  }
}
