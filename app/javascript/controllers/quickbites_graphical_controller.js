import { Controller } from "@hotwired/stimulus"
import { buildButton, buildInput, buildFieldGroup } from "../utilities/dom_builders"
import { toggleAccordionItem, expandAccordionItem, buildToggleButton } from "../utilities/accordion"
import { structureChanged } from "../utilities/editor_utils"

/**
 * Form-based Quick Bites editor: structured fields for categories containing
 * items. Each category is a collapsible accordion card with item rows (name +
 * ingredients). Produces an IR hash matching QuickBitesSerializer output for
 * the structured save path. Simpler than the recipe graphical editor — only
 * two levels (categories with items, no steps/instructions).
 *
 * - dual_mode_editor_controller: coordinator, routes lifecycle events
 * - editor_controller: dialog lifecycle
 */
export default class extends Controller {
  static targets = ["categoriesContainer"]

  connect() {
    this.categories = []
  }

  loadStructure(ir) {
    this.categories = (ir.categories || []).map(cat => ({
      name: cat.name || "",
      items: (cat.items || []).map(item => ({ ...item }))
    }))
    this.rebuildCategories()
    if (this.categories.length > 0) expandAccordionItem(this.categoriesContainerTarget, 0)
  }

  toStructure() {
    return { categories: this.serializeCategories() }
  }

  isModified(original) {
    return structureChanged(this.toStructure(), original)
  }

  addCategory() {
    this.categories.push({ name: "", items: [] })
    this.appendCategoryCard(this.categories.length - 1, this.categories.at(-1))
    expandAccordionItem(this.categoriesContainerTarget, this.categories.length - 1)
  }

  // --- Category Management ---

  removeCategory(index) {
    this.categories.splice(index, 1)
    this.rebuildCategories()
  }

  moveCategory(index, direction) {
    const target = index + direction
    if (target < 0 || target >= this.categories.length) return

    const [moved] = this.categories.splice(index, 1)
    this.categories.splice(target, 0, moved)
    this.rebuildCategories()
    expandAccordionItem(this.categoriesContainerTarget, target)
  }

  rebuildCategories() {
    this.categoriesContainerTarget.replaceChildren()
    this.categories.forEach((cat, i) => this.appendCategoryCard(i, cat))
  }

  appendCategoryCard(index, catData) {
    this.categoriesContainerTarget.appendChild(this.buildCategoryCard(index, catData))
  }

  // --- Item Management ---

  addItem(catIndex) {
    if (!this.categories[catIndex].items) this.categories[catIndex].items = []
    this.categories[catIndex].items.push({ name: "", ingredients: [] })
    this.rebuildItemRows(catIndex)
  }

  removeItem(catIndex, itemIndex) {
    this.categories[catIndex].items.splice(itemIndex, 1)
    this.rebuildItemRows(catIndex)
  }

  moveItem(catIndex, itemIndex, direction) {
    const items = this.categories[catIndex].items
    const target = itemIndex + direction
    if (target < 0 || target >= items.length) return

    const [moved] = items.splice(itemIndex, 1)
    items.splice(target, 0, moved)
    this.rebuildItemRows(catIndex)
  }

  rebuildItemRows(catIndex) {
    const container = this.categoriesContainerTarget
      .querySelector(`.graphical-ingredient-rows[data-cat-index="${catIndex}"]`)
    if (!container) return

    container.replaceChildren()
    const items = this.categories[catIndex].items || []
    items.forEach((item, i) => {
      container.appendChild(this.buildItemRow(catIndex, i, item))
    })
  }

  // --- Serialization ---

  serializeCategories() {
    return this.categories.map(cat => ({
      name: cat.name.trim(),
      items: this.serializeItems(cat.items)
    }))
  }

  serializeItems(items) {
    if (!items) return []
    return items
      .filter(item => item.name && item.name.trim() !== "")
      .map(item => this.serializeItem(item))
  }

  serializeItem(item) {
    const name = item.name.trim()
    const rawIngredients = this.parseIngredientsList(item)
    const ingredients = rawIngredients.length > 0 ? rawIngredients : [name]
    return { name, ingredients }
  }

  parseIngredientsList(item) {
    if (!item.ingredientsText) return item.ingredients || []
    return item.ingredientsText
      .split(",")
      .map(s => s.trim())
      .filter(s => s !== "")
  }

  // --- Category Card DOM Builder ---

  buildCategoryCard(index, catData) {
    const card = document.createElement("div")
    card.className = "graphical-step-card"
    card.appendChild(this.buildCategoryHeader(index, catData))
    card.appendChild(this.buildCategoryBody(index, catData))
    return card
  }

  buildCategoryHeader(index, catData) {
    const header = document.createElement("div")
    header.className = "graphical-step-header"
    header.addEventListener("click", (e) => {
      if (e.target.closest(".graphical-step-actions") || e.target.closest(".graphical-step-toggle")) return
      toggleAccordionItem(this.categoriesContainerTarget, index)
    })

    header.appendChild(buildToggleButton(() => toggleAccordionItem(this.categoriesContainerTarget, index)))
    header.appendChild(this.buildCategoryTitle(index, catData))
    header.appendChild(this.buildItemSummary(catData))
    header.appendChild(this.buildCategoryActions(index))
    return header
  }

  buildCategoryTitle(index, catData) {
    const span = document.createElement("span")
    span.className = "graphical-step-title"
    span.textContent = catData.name || `Category ${index + 1}`
    return span
  }

  buildItemSummary(catData) {
    const span = document.createElement("span")
    span.className = "graphical-ingredient-summary"
    const count = (catData.items || []).length
    span.textContent = count === 0 ? "" : `${count} item${count === 1 ? "" : "s"}`
    return span
  }

  buildCategoryActions(index) {
    const actions = document.createElement("div")
    actions.className = "graphical-step-actions"

    actions.appendChild(buildButton("\u2191", () => this.moveCategory(index, -1), "graphical-btn--icon"))
    actions.appendChild(buildButton("\u2193", () => this.moveCategory(index, 1), "graphical-btn--icon"))
    actions.appendChild(buildButton("\u00D7", () => this.removeCategory(index), "graphical-btn--icon graphical-btn--danger"))
    return actions
  }

  buildCategoryBody(index, catData) {
    const body = document.createElement("div")
    body.className = "graphical-step-body"
    body.hidden = true

    body.appendChild(buildFieldGroup("Category name", "text", catData.name || "", (val) => {
      this.categories[index].name = val
      this.updateCategoryTitleDisplay(index)
    }))

    body.appendChild(this.buildItemsSection(index, catData.items || []))
    return body
  }

  updateCategoryTitleDisplay(index) {
    const card = this.categoriesContainerTarget.children[index]
    if (!card) return
    const titleEl = card.querySelector(".graphical-step-title")
    if (titleEl) titleEl.textContent = this.categories[index].name || `Category ${index + 1}`
  }

  // --- Item Rows ---

  buildItemsSection(catIndex, items) {
    const section = document.createElement("div")
    section.className = "graphical-ingredients-section"

    const headerRow = document.createElement("div")
    headerRow.className = "graphical-ingredients-header"

    const label = document.createElement("span")
    label.textContent = "Items"
    headerRow.appendChild(label)

    headerRow.appendChild(buildButton("+ Add", () => this.addItem(catIndex), "graphical-btn--small"))
    section.appendChild(headerRow)

    const rowsContainer = document.createElement("div")
    rowsContainer.className = "graphical-ingredient-rows"
    rowsContainer.dataset.catIndex = catIndex
    items.forEach((item, i) => {
      rowsContainer.appendChild(this.buildItemRow(catIndex, i, item))
    })
    section.appendChild(rowsContainer)

    return section
  }

  buildItemRow(catIndex, itemIndex, item) {
    const row = document.createElement("div")
    row.className = "graphical-ingredient-row"

    row.appendChild(buildInput("Item name", item.name || "", (val) => {
      this.categories[catIndex].items[itemIndex].name = val
    }, "graphical-input--name"))

    const ingredientsText = this.ingredientsDisplayText(item)
    row.appendChild(buildInput("Ingredients (comma-separated)", ingredientsText, (val) => {
      this.categories[catIndex].items[itemIndex].ingredientsText = val
    }, "graphical-input--prep"))

    const actions = document.createElement("div")
    actions.className = "graphical-ingredient-actions"
    actions.appendChild(buildButton("\u2191", () => this.moveItem(catIndex, itemIndex, -1), "graphical-btn--icon"))
    actions.appendChild(buildButton("\u2193", () => this.moveItem(catIndex, itemIndex, 1), "graphical-btn--icon"))
    actions.appendChild(buildButton("\u00D7", () => this.removeItem(catIndex, itemIndex), "graphical-btn--icon graphical-btn--danger"))
    row.appendChild(actions)

    return row
  }

  ingredientsDisplayText(item) {
    if (item.ingredientsText !== undefined) return item.ingredientsText
    if (!item.ingredients || item.ingredients.length === 0) return ""
    if (item.ingredients.length === 1 && item.ingredients[0] === item.name) return ""
    return item.ingredients.join(", ")
  }
}
