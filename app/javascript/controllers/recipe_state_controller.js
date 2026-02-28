import { Controller } from "@hotwired/stimulus"
import { formatVulgar, isVulgarSingular } from "utilities/vulgar_fractions"

const STORED_STATE_TTL = 48 * 60 * 60 * 1000

export default class extends Controller {
  connect() {
    this.recipeId = document.body.dataset.recipeId
    this.versionHash = document.body.dataset.versionHash
    this.lastScaleInput = '1'

    this.crossableItemNodes = this.element.querySelectorAll(
      '.ingredients li, .instructions p'
    )
    this.sectionTogglerNodes = this.element.querySelectorAll('section h2')

    this.boundHandlers = new Map()
    this.setupEventListeners()
    this.loadRecipeState()
    this.setupScaleButton()
    this.updateScaleButtonLabel()
  }

  disconnect() {
    for (const [node, handlers] of this.boundHandlers) {
      for (const [event, handler] of handlers) {
        node.removeEventListener(event, handler)
      }
    }
    this.boundHandlers.clear()
  }

  addListener(node, event, handler) {
    node.addEventListener(event, handler)
    if (!this.boundHandlers.has(node)) this.boundHandlers.set(node, [])
    this.boundHandlers.get(node).push([event, handler])
  }

  saveRecipeState() {
    const currentRecipeState = {
      lastInteractionTime: Date.now(),
      versionHash: this.versionHash,
      crossableItemState: {},
      scaleFactor: this.lastScaleInput
    }

    this.crossableItemNodes.forEach((node, idx) => {
      currentRecipeState.crossableItemState[idx] =
        node.classList.contains('crossed-off')
    })

    localStorage.setItem(
      `saved-state-for-${this.recipeId}`,
      JSON.stringify(currentRecipeState)
    )
  }

  loadRecipeState() {
    const raw = localStorage.getItem(`saved-state-for-${this.recipeId}`)
    if (!raw) return

    let stored
    try {
      stored = JSON.parse(raw)
    } catch {
      console.warn('Corrupt state JSON. Resetting.')
      return this.saveRecipeState()
    }

    const { versionHash, lastInteractionTime, crossableItemState, scaleFactor } = stored

    if (
      versionHash !== this.versionHash ||
      Date.now() - lastInteractionTime > STORED_STATE_TTL
    ) {
      console.info('Saved state stale or mismatched. Overwriting.')
      return this.saveRecipeState()
    }

    this.crossableItemNodes.forEach((node, idx) => {
      if (crossableItemState[idx]) node.classList.add('crossed-off')
    })

    if (scaleFactor) {
      this.lastScaleInput = scaleFactor
      this.applyScale(scaleFactor)
      this.updateScaleButtonLabel()
    }
  }

  setupEventListeners() {
    this.crossableItemNodes.forEach(node => {
      node.tabIndex = 0

      const clickHandler = (e) => {
        if (e.target.closest('a')) return
        node.classList.toggle('crossed-off')
        this.saveRecipeState()
      }

      const keyHandler = (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          if (e.target.closest('a')) return
          e.preventDefault()
          node.classList.toggle('crossed-off')
          this.saveRecipeState()
        }
      }

      this.addListener(node, 'click', clickHandler)
      this.addListener(node, 'keydown', keyHandler)
    })

    this.sectionTogglerNodes.forEach(h2 => {
      const handler = () => {
        const section = h2.closest('section')
        const items = section.querySelectorAll(
          '.ingredients li, .instructions p'
        )
        const allCrossed = Array.from(items).every(i =>
          i.classList.contains('crossed-off')
        )
        items.forEach(i => i.classList.toggle('crossed-off', !allCrossed))
        this.saveRecipeState()
      }

      this.addListener(h2, 'click', handler)
    })
  }

  setupScaleButton() {
    const btn = document.getElementById('scale-button')
    if (!btn) return

    const handler = () => {
      const input = prompt(
        'Scale ingredients by factor (e.g. 2 or 3/2):',
        this.lastScaleInput
      )
      if (!input) return

      const factor = this.parseFactor(input)
      if (!(factor > 0 && isFinite(factor))) {
        alert(
          'Invalid scale. Please enter a positive number or fraction (e.g. "2" or "3/2"), and make sure denominator isn\'t zero.'
        )
        return
      }

      this.lastScaleInput = input
      this.applyScale(input)
      this.updateScaleButtonLabel()
      this.saveRecipeState()
    }

    this.addListener(btn, 'click', handler)
  }

  applyScale(rawInput) {
    const factor = this.parseFactor(rawInput)

    this.element
      .querySelectorAll('li[data-quantity-value]')
      .forEach(li => {
        const orig = parseFloat(li.dataset.quantityValue)
        const unitSingular = li.dataset.quantityUnit || ''
        const unitPlural = li.dataset.quantityUnitPlural || unitSingular
        const scaled = orig * factor
        const unit = isVulgarSingular(scaled) ? unitSingular : unitPlural
        const pretty = formatVulgar(scaled)
        const span = li.querySelector('.quantity')
        if (span) span.textContent = pretty + (unit ? ' ' + unit : '')

        const nameEl = li.querySelector('.ingredient-name')
        if (nameEl && li.dataset.nameSingular) {
          nameEl.textContent = isVulgarSingular(scaled)
            ? li.dataset.nameSingular
            : li.dataset.namePlural
        }
      })

    this.element.querySelectorAll('.nutrition-facts td[data-nutrient]').forEach(td => {
      const base = parseFloat(td.dataset.baseValue)
      const scaled = base * factor
      const nutrient = td.dataset.nutrient
      const unit = (nutrient === 'sodium' || nutrient === 'cholesterol') ? 'mg' : (nutrient === 'calories' ? '' : 'g')
      td.textContent = Math.round(scaled) + unit
    })

    this.element.querySelectorAll('.scalable[data-base-value]').forEach(span => {
      if (span.closest('.yield')) return
      if (factor === 1) {
        span.textContent = span.dataset.originalText
        span.classList.remove('scaled')
        span.removeAttribute('title')
      } else {
        const base = parseFloat(span.dataset.baseValue)
        const scaled = base * factor
        const pretty = Number.isInteger(scaled)
          ? scaled
          : Math.round(scaled * 100) / 100
        span.textContent = String(pretty)
        span.classList.add('scaled')
        span.title = 'Originally: ' + span.dataset.originalText
      }
    })

    this.element.querySelectorAll('.yield[data-base-value]').forEach(container => {
      const base = parseFloat(container.dataset.baseValue)
      const scaled = base * factor
      const singular = container.dataset.unitSingular || ''
      const plural = container.dataset.unitPlural || singular

      const scalableSpan = container.querySelector('.scalable')
      const unitSpan = container.querySelector('.yield-unit')
      if (!scalableSpan || !unitSpan) return

      if (factor === 1) {
        scalableSpan.textContent = scalableSpan.dataset.originalText
        scalableSpan.classList.remove('scaled')
        scalableSpan.removeAttribute('title')
        unitSpan.textContent = ' ' + (isVulgarSingular(base) ? singular : plural)
      } else {
        const pretty = formatVulgar(scaled)
        const unit = isVulgarSingular(scaled) ? singular : plural
        scalableSpan.textContent = pretty
        scalableSpan.classList.add('scaled')
        scalableSpan.title = 'Originally: ' + scalableSpan.dataset.originalText
        unitSpan.textContent = ' ' + unit
      }
    })
  }

  updateScaleButtonLabel() {
    const btn = document.getElementById('scale-button')
    if (!btn) return

    const factor = this.parseFactor(this.lastScaleInput)
    if (factor === 1) {
      btn.textContent = 'Scale'
    } else {
      const pretty = Number.isInteger(factor)
        ? factor
        : Math.round(factor * 100) / 100
      btn.textContent = `Scale (x${pretty})`
    }
  }

  parseFactor(str) {
    str = str.trim()
    const frac = str.match(/^(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)$/)
    if (frac) return parseFloat(frac[1]) / parseFloat(frac[2])
    const num = parseFloat(str)
    return isNaN(num) ? NaN : num
  }
}
