import { Controller } from "@hotwired/stimulus"
import { formatVulgar, isVulgarSingular } from "utilities/vulgar_fractions"
import ListenerManager from "utilities/listener_manager"

/**
 * Recipe page progressive enhancement: cross-off (click to strike through
 * ingredients/instructions), section toggling (click h2 to cross off entire
 * step), and ingredient scaling. State is persisted to localStorage keyed by
 * recipe ID and version hash — stale or mismatched state is discarded.
 *
 * Top-level instances own scaling; embedded instances (cross-references) only
 * handle cross-off state. The `embedded` value flag distinguishes the two —
 * embedded controllers skip scale factor persistence and restoration, deferring
 * to the parent recipe's scale_panel_controller for coordinated scaling.
 *
 * - vulgar_fractions: formats scaled quantities as Unicode fraction glyphs
 * - ListenerManager: tracks event listeners for clean teardown on disconnect
 */
const STORED_STATE_TTL = 48 * 60 * 60 * 1000

export default class extends Controller {
  static values = { recipeId: String, versionHash: String, embedded: Boolean }

  connect() {
    this.recipeId = this.hasRecipeIdValue ? this.recipeIdValue : document.body.dataset.recipeId
    this.versionHash = this.hasVersionHashValue ? this.versionHashValue : document.body.dataset.versionHash

    this.crossableItemNodes = Array.from(
      this.element.querySelectorAll('.ingredients li, .instructions p')
    ).filter(node => node.closest('[data-controller*="recipe-state"]') === this.element)
    this.sectionTogglerNodes = Array.from(
      this.element.querySelectorAll('section :is(h2, h3)')
    ).filter(node => node.closest('[data-controller*="recipe-state"]') === this.element)

    this.listeners = new ListenerManager()
    this.setupEventListeners()
    this.loadRecipeState()

    if (!this.embeddedValue) {
      this.boundOnScaleChange = (e) => {
        this.scaleFactor = e.detail.factor
        this.applyScale(e.detail.factor)
        this.saveRecipeState()
      }
      this.element.addEventListener('scale-panel:change', this.boundOnScaleChange)
    }
  }

  disconnect() {
    this.listeners.teardown()
    if (this.boundOnScaleChange) {
      this.element.removeEventListener('scale-panel:change', this.boundOnScaleChange)
    }
  }

  saveRecipeState() {
    const state = {
      lastInteractionTime: Date.now(),
      versionHash: this.versionHash,
      crossableItemState: {}
    }

    if (!this.embeddedValue) state.scaleFactor = this.scaleFactor || 1

    this.crossableItemNodes.forEach((node, idx) => {
      state.crossableItemState[idx] = node.classList.contains('crossed-off')
    })

    localStorage.setItem(`saved-state-for-${this.recipeId}`, JSON.stringify(state))
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

    if (scaleFactor && !this.embeddedValue) {
      const factor = typeof scaleFactor === 'string' ? parseFloat(scaleFactor) : scaleFactor
      if (factor && isFinite(factor)) {
        this.scaleFactor = factor
        this.applyScale(factor)
        this.element.dataset.restoredScaleFactor = factor
        this.dispatch('restored', { detail: { factor }, bubbles: false })
      }
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

      this.listeners.add(node, 'click', clickHandler)
      this.listeners.add(node, 'keydown', keyHandler)
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

      this.listeners.add(h2, 'click', handler)
    })
  }

  applyScale(factor) {
    this.element
      .querySelectorAll('li[data-quantity-value]')
      .forEach(li => {
        const orig = parseFloat(li.dataset.quantityValue)
        const unitSingular = li.dataset.quantityUnit || ''
        const unitPlural = li.dataset.quantityUnitPlural || unitSingular
        const scaled = orig * factor
        const unit = isVulgarSingular(scaled) ? unitSingular : unitPlural
        const pretty = formatVulgar(scaled, unitSingular)
        const span = li.querySelector('.quantity')
        if (span) span.textContent = pretty + (unit ? ` ${unit}` : '')

        const nameEl = li.querySelector('.ingredient-name')
        if (nameEl && li.dataset.nameSingular) {
          nameEl.textContent = isVulgarSingular(scaled)
            ? li.dataset.nameSingular
            : li.dataset.namePlural
        }
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
        span.title = `Originally: ${span.dataset.originalText}`
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
        unitSpan.textContent = ` ${isVulgarSingular(base) ? singular : plural}`
      } else {
        const pretty = formatVulgar(scaled)
        const unit = isVulgarSingular(scaled) ? singular : plural
        scalableSpan.textContent = pretty
        scalableSpan.classList.add('scaled')
        scalableSpan.title = `Originally: ${scalableSpan.dataset.originalText}`
        unitSpan.textContent = ` ${unit}`
      }
    })

    this.element.querySelectorAll('article.embedded-recipe[data-base-multiplier]').forEach(article => {
      const base = parseFloat(article.dataset.baseMultiplier)
      const effective = base * factor
      const badge = article.querySelector('.embedded-multiplier')
      if (!badge) return

      if (Math.abs(effective - 1) < 0.001) {
        badge.hidden = true
      } else {
        badge.hidden = false
        const pretty = Number.isInteger(effective)
          ? effective
          : Math.round(effective * 100) / 100
        badge.textContent = `\u00D7 ${pretty}`
      }
    })
  }

}
