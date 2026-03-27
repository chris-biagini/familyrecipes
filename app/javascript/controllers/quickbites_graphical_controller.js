import { Controller } from "@hotwired/stimulus"
import { buildInput, buildFieldGroup, buildIconButton } from "../utilities/dom_builders"
import { structureChanged } from "../utilities/editor_utils"
import {
  expandItem,
  removeFromList, moveInList, rebuildContainer,
  buildCardShell, buildCardDetails, buildCardTitle, buildCountSummary,
  buildCardActions, buildCollapseBody, buildRowsSection, updateTitleDisplay
} from "../utilities/graphical_editor_utils"

/**
 * Form-based Quick Bites editor: structured fields for categories containing
 * items. Each category is a collapsible card using native <details> with CSS
 * grid animation. Produces an IR hash matching QuickBitesSerializer output for
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
    if (this.categoriesContainerTarget.children.length > 0) this.initFromRenderedDOM()
  }

  initFromRenderedDOM() {
    const cards = this.categoriesContainerTarget.children
    this.categories = Array.from(cards).map(card => this.readCategoryFromCard(card))
    this.rebuildCategories()
    if (this.categories.length > 0) expandItem(this.categoriesContainerTarget, 0)
  }

  readCategoryFromCard(card) {
    const body = card.querySelector(".graphical-step-body")
    return {
      name: body?.querySelector("[data-field='name']")?.value || "",
      items: this.readItemsFromCard(card)
    }
  }

  readItemsFromCard(card) {
    const rows = card.querySelectorAll(".graphical-ingredient-row")
    return Array.from(rows).map(row => ({
      name: row.querySelector("[data-field='item-name']")?.value || "",
      ingredientsText: row.querySelector("[data-field='ingredients-text']")?.value || ""
    }))
  }

  loadStructure(ir) {
    this.categories = (ir.categories || []).map(cat => ({
      name: cat.name || "",
      items: (cat.items || []).map(item => ({ ...item }))
    }))
    this.rebuildCategories()
    if (this.categories.length > 0) expandItem(this.categoriesContainerTarget, 0)
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
    expandItem(this.categoriesContainerTarget, this.categories.length - 1)
  }

  // --- Category Management ---

  removeCategory(index) {
    removeFromList(this.categories, index, () => this.rebuildCategories())
  }

  moveCategory(index, direction) {
    moveInList(this.categories, index, direction, this.categoriesContainerTarget, () => this.rebuildCategories())
  }

  rebuildCategories() {
    rebuildContainer(this.categoriesContainerTarget, this.categories, (i, cat) => this.buildCategoryCard(i, cat))
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
    removeFromList(this.categories[catIndex].items, itemIndex, () => this.rebuildItemRows(catIndex))
  }

  moveItem(catIndex, itemIndex, direction) {
    moveInList(this.categories[catIndex].items, itemIndex, direction, null, () => this.rebuildItemRows(catIndex))
  }

  rebuildItemRows(catIndex) {
    const container = this.categoriesContainerTarget
      .querySelector(`.graphical-ingredient-rows[data-cat-index="${catIndex}"]`)
    if (!container) return
    rebuildContainer(container, this.categories[catIndex].items || [],
      (i, item) => this.buildItemRow(catIndex, i, item))
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
    return buildCardShell(
      this.buildCategoryDetails(index, catData),
      this.buildCategoryCollapseBody(index, catData)
    )
  }

  buildCategoryDetails(index, catData) {
    return buildCardDetails(
      buildCardTitle(catData.name, `Category ${index + 1}`),
      buildCountSummary((catData.items || []).length, "item", "items"),
      buildCardActions(index, (i, dir) => this.moveCategory(i, dir), (i) => this.removeCategory(i))
    )
  }

  buildCategoryCollapseBody(index, catData) {
    return buildCollapseBody(inner => {
      inner.appendChild(buildFieldGroup("Category name", "text", catData.name || "", (val) => {
        this.categories[index].name = val
        updateTitleDisplay(this.categoriesContainerTarget, index, val, `Category ${index + 1}`)
      }))

      inner.appendChild(this.buildItemsSection(index, catData.items || []))
    })
  }

  // --- Item Rows ---

  buildItemsSection(catIndex, items) {
    return buildRowsSection(
      "Items",
      items,
      () => this.addItem(catIndex),
      (i, item) => this.buildItemRow(catIndex, i, item),
      { catIndex }
    )
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
    actions.appendChild(buildIconButton("chevron", () => this.moveItem(catIndex, itemIndex, -1), { label: "Move up" }))
    const downBtn = buildIconButton("chevron", () => this.moveItem(catIndex, itemIndex, 1), { className: "aisle-icon--flipped", label: "Move down" })
    actions.appendChild(downBtn)
    actions.appendChild(buildIconButton("delete", () => this.removeItem(catIndex, itemIndex), { className: "btn-danger", label: "Remove" }))
    row.appendChild(actions)

    return row
  }

  focusCategory(name) {
    const index = this.categories.findIndex(cat => cat.name === name)
    if (index >= 0) {
      expandItem(this.categoriesContainerTarget, index)
    }
  }

  ingredientsDisplayText(item) {
    if (item.ingredientsText !== undefined) return item.ingredientsText
    if (!item.ingredients || item.ingredients.length === 0) return ""
    if (item.ingredients.length === 1 && item.ingredients[0] === item.name) return ""
    return item.ingredients.join(", ")
  }
}
