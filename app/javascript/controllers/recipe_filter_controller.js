/**
 * Client-side tag filtering for the cookbook index page.
 *
 * Mounted on `#recipe-listings`. Manages a set of active tag names and
 * toggles CSS classes on recipe cards, category sections, and TOC links
 * to show/hide based on tag matches.
 *
 * Collaborators:
 *   - `_recipe_listings.html.erb` provides targets and data-tags attributes
 *   - `base.css` defines `.filtered-out`, `.filtered-empty`, `.active` styles
 */
import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static targets = ['tag', 'card', 'category', 'tocLink']

  connect () {
    this.activeTags = new Set()
  }

  toggle (event) {
    const pill = event.currentTarget
    const name = pill.dataset.tag

    if (this.activeTags.has(name)) {
      this.activeTags.delete(name)
      pill.classList.remove('active')
    } else {
      this.activeTags.add(name)
      pill.classList.add('active')
    }

    this.apply()
  }

  apply () {
    const active = this.activeTags
    const filtering = active.size > 0

    this.cardTargets.forEach(card => {
      if (!filtering) {
        card.classList.remove('filtered-out')
        return
      }

      const cardTags = (card.dataset.tags || '').split(',').filter(Boolean)
      const matches = [...active].every(tag => cardTags.includes(tag))
      card.classList.toggle('filtered-out', !matches)
    })

    this.categoryTargets.forEach(section => {
      if (!filtering) {
        section.classList.remove('filtered-empty')
        return
      }

      const cards = section.querySelectorAll('[data-recipe-filter-target="card"]')
      const allHidden = [...cards].every(c => c.classList.contains('filtered-out'))
      section.classList.toggle('filtered-empty', allHidden)
    })

    this.tocLinkTargets.forEach(li => {
      if (!filtering) {
        li.classList.remove('filtered-empty')
        return
      }

      const slug = li.dataset.category
      const section = document.getElementById(slug)
      if (section) {
        li.classList.toggle('filtered-empty', section.classList.contains('filtered-empty'))
      }
    })
  }
}
