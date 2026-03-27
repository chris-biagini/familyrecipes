import { Controller } from "@hotwired/stimulus"
import { buildInput, buildFieldGroup, buildTextareaGroup, buildIconButton } from "../utilities/dom_builders"
import { structureChanged } from "../utilities/editor_utils"
import {
  expandItem, toggleItem,
  removeFromList, moveInList, rebuildContainer,
  buildCardShell, buildCardDetails, buildCardTitle, buildCountSummary,
  buildCardActions, buildCollapseBody, buildRowsSection, updateTitleDisplay,
  updateMoveButtons
} from "../utilities/graphical_editor_utils"

/**
 * Form-based recipe editor: structured fields for title, description,
 * front matter, steps (with ingredients), and footer. Produces an IR
 * hash matching RecipeBuilder output for the structured import path.
 * Cross-reference steps render as read-only cards.
 *
 * - dual_mode_editor_controller: coordinator, routes lifecycle events
 * - tag_input_controller: nested, tag pill management
 * - editor_controller: dialog lifecycle
 */
export default class extends Controller {
  static targets = [
    "title", "description", "serves", "makes",
    "categorySelect", "categoryInput", "categoryRow",
    "stepsContainer", "footer"
  ]

  connect() {
    this.steps = []
    if (this.stepsContainerTarget.children.length > 0) this.initFromRenderedDOM()
  }

  initFromRenderedDOM() {
    const cards = this.stepsContainerTarget.children
    this.steps = Array.from(cards).map(card => this.readStepFromCard(card))
    this.rebuildSteps()
    if (this.steps.length > 0) expandItem(this.stepsContainerTarget, 0)
  }

  readStepFromCard(card) {
    if (card.classList.contains("graphical-step-card--crossref")) {
      const label = card.querySelector(".graphical-crossref-label")?.textContent || ""
      const match = label.match(/Imports from (.+?)(?:\s*\u00d7([\d.]+))?$/)
      return {
        cross_reference: {
          target_title: match?.[1]?.trim() || "",
          multiplier: match?.[2] ? parseFloat(match[2]) : null
        }
      }
    }

    const body = card.querySelector(".graphical-step-body")
    return {
      tldr: body?.querySelector("[data-field='tldr']")?.value || "",
      ingredients: this.readIngredientsFromCard(card),
      instructions: body?.querySelector("[data-field='instructions']")?.value || "",
      cross_reference: null
    }
  }

  readIngredientsFromCard(card) {
    const rows = card.querySelectorAll(".graphical-ingredient-card")
    return Array.from(rows).map(row => ({
      name: row.querySelector("[data-field='name']")?.value || "",
      quantity: row.querySelector("[data-field='quantity']")?.value || "",
      prep_note: row.querySelector("[data-field='prep_note']")?.value || ""
    }))
  }

  // --- Public API (for coordinator) ---

  loadStructure(ir) {
    this.titleTarget.value = ir.title || ""
    this.descriptionTarget.value = ir.description || ""
    this.loadFrontMatter(ir.front_matter)
    this.loadSteps(ir.steps || [])
    this.footerTarget.value = ir.footer || ""
  }

  toStructure() {
    return {
      title: this.titleTarget.value.trim(),
      description: this.descriptionTarget.value.trim() || null,
      front_matter: this.buildFrontMatter(),
      steps: this.serializeSteps(),
      footer: this.footerTarget.value.trim() || null
    }
  }

  isModified(original) {
    return structureChanged(this.toStructure(), original)
  }

  addStep(data) {
    const stepData = data || this.emptyStep()
    this.steps.push(stepData)
    this.appendStepCard(this.steps.length - 1, stepData)
  }

  // --- Front Matter ---

  loadFrontMatter(fm) {
    if (!fm) return
    this.servesTarget.value = fm.serves || ""
    this.makesTarget.value = fm.makes || ""
    this.setCategoryFromIR(fm.category)
    this.loadTagsFromIR(fm.tags || [])
  }

  buildFrontMatter() {
    const fm = {}
    const makes = this.makesTarget.value.trim()
    if (makes) fm.makes = makes
    const serves = this.servesTarget.value.trim()
    if (serves) fm.serves = serves
    const category = this.selectedCategory()
    if (category) fm.category = category
    const tags = this.tagController?.tags || []
    if (tags.length > 0) fm.tags = tags
    return fm
  }

  // --- Category ---

  selectedCategory() {
    if (!this.hasCategorySelectTarget) return null
    const val = this.categorySelectTarget.value
    if (val === "__new__") {
      return this.hasCategoryInputTarget ? this.categoryInputTarget.value.trim() : null
    }
    return val || null
  }

  setCategoryFromIR(category) {
    if (!this.hasCategorySelectTarget || !category) return

    const options = Array.from(this.categorySelectTarget.options)
    const match = options.find(o => o.value === category)

    if (match) {
      this.categorySelectTarget.value = category
    } else {
      this.showNewCategoryInput(category)
    }
  }

  showNewCategoryInput(value) {
    this.categorySelectTarget.value = "__new__"
    if (!this.hasCategoryRowTarget) return
    this.categoryInputTarget.value = value || ""
    this.categoryRowTarget.hidden = false
  }

  categoryChanged() {
    if (!this.hasCategoryRowTarget) return
    if (this.categorySelectTarget.value === "__new__") {
      this.categoryRowTarget.hidden = false
      this.categoryInputTarget.focus()
    } else {
      this.categoryRowTarget.hidden = true
    }
  }

  categoryInputKeydown(event) {
    if (event.key !== "Escape") return
    this.cancelNewCategory()
  }

  cancelNewCategory() {
    if (!this.hasCategoryRowTarget) return
    this.categoryRowTarget.hidden = true
    this.categorySelectTarget.value = ""
  }

  // --- Tags ---

  get tagController() {
    const el = this.element.querySelector("[data-controller~='tag-input']")
    return el ? this.application.getControllerForElementAndIdentifier(el, "tag-input") : null
  }

  loadTagsFromIR(tags) {
    this.tagController?.loadTags(tags)
  }

  // --- Step Management ---

  loadSteps(stepsData) {
    this.steps = stepsData.map(s => ({ ...s }))
    this.rebuildSteps()
    if (this.steps.length > 0) expandItem(this.stepsContainerTarget, 0)
  }

  removeStep(index) {
    if (this.steps.length <= 1) return
    removeFromList(this.steps, index, () => this.rebuildSteps())
  }

  moveStep(index, direction) {
    moveInList(this.steps, index, direction, this.stepsContainerTarget, () => this.rebuildSteps())
  }

  rebuildSteps() {
    rebuildContainer(this.stepsContainerTarget, this.steps, (i, step) => this.buildStepCard(i, step))
    updateMoveButtons(this.stepsContainerTarget)
  }

  appendStepCard(index, stepData) {
    this.stepsContainerTarget.appendChild(this.buildStepCard(index, stepData))
  }

  findExpandedIndex() {
    const cards = this.stepsContainerTarget.children
    for (let i = 0; i < cards.length; i++) {
      const details = cards[i].querySelector("details.collapse-header")
      if (details?.open) return i
    }
    return -1
  }

  // --- Step Card DOM Builder ---

  buildStepCard(index, stepData) {
    if (stepData.cross_reference) return this.buildCrossRefCard(index, stepData)

    return buildCardShell(
      this.buildStepDetails(index, stepData),
      this.buildStepCollapseBody(index, stepData)
    )
  }

  buildCrossRefCard(index, stepData) {
    const card = document.createElement("div")
    card.className = "graphical-step-card graphical-step-card--crossref"

    const header = document.createElement("div")
    header.className = "graphical-step-header"

    const label = document.createElement("span")
    label.className = "graphical-crossref-label"
    label.textContent = this.crossRefLabel(stepData.cross_reference)
    header.appendChild(label)

    const hint = document.createElement("span")
    hint.className = "graphical-crossref-hint"
    hint.textContent = "edit in </> mode"
    header.appendChild(hint)

    header.appendChild(buildCardActions(index, (i, dir) => this.moveStep(i, dir), (i) => this.removeStep(i), { total: this.steps.length }))
    card.appendChild(header)
    return card
  }

  crossRefLabel(xref) {
    let label = `Imports from ${xref.target_title}`
    if (xref.multiplier && Math.abs(xref.multiplier - 1.0) > 0.0001) {
      label += ` \u00D7${xref.multiplier}`
    }
    return label
  }

  buildStepDetails(index, stepData) {
    return buildCardDetails(
      buildCardTitle(stepData.tldr, `Step ${index + 1}`),
      buildCountSummary((stepData.ingredients || []).length, "ingredient", "ingredients"),
      buildCardActions(index, (i, dir) => this.moveStep(i, dir), (i) => this.removeStep(i), { total: this.steps.length })
    )
  }

  buildStepCollapseBody(index, stepData) {
    return buildCollapseBody(inner => {
      inner.appendChild(buildFieldGroup("Step name", "text", stepData.tldr || "", (val) => {
        this.steps[index].tldr = val
        updateTitleDisplay(this.stepsContainerTarget, index, val, `Step ${index + 1}`)
      }))

      inner.appendChild(this.buildIngredientsSection(index, stepData.ingredients || []))

      inner.appendChild(buildTextareaGroup("Instructions", stepData.instructions || "", (val) => {
        this.steps[index].instructions = val
      }))
    })
  }

  // --- Ingredient Rows ---

  buildIngredientsSection(stepIndex, ingredients) {
    return buildRowsSection(
      "Ingredients",
      ingredients,
      () => this.addIngredient(stepIndex),
      (i, ing) => this.buildIngredientRow(stepIndex, i, ing),
      { stepIndex }
    )
  }

  buildIngredientRow(stepIndex, ingIndex, ing) {
    const card = document.createElement("div")
    card.className = "graphical-ingredient-card"

    const fields = document.createElement("div")
    fields.className = "graphical-ingredient-fields"

    fields.appendChild(buildInput("Name", ing.name || "", (val) => {
      this.steps[stepIndex].ingredients[ingIndex].name = val
    }, "graphical-ing-name"))

    fields.appendChild(buildInput("Qty", ing.quantity || "", (val) => {
      this.steps[stepIndex].ingredients[ingIndex].quantity = val
    }, "graphical-ing-qty"))

    fields.appendChild(buildInput("Prep note", ing.prep_note || "", (val) => {
      this.steps[stepIndex].ingredients[ingIndex].prep_note = val
    }, "graphical-ing-prep"))

    card.appendChild(fields)

    const total = this.steps[stepIndex].ingredients.length
    const actions = document.createElement("div")
    actions.className = "graphical-ingredient-actions"
    const upBtn = buildIconButton("chevron", () => this.moveIngredient(stepIndex, ingIndex, -1), { className: "btn-move-up", label: "Move up" })
    if (ingIndex === 0) upBtn.disabled = true
    actions.appendChild(upBtn)
    const downBtn = buildIconButton("chevron", () => this.moveIngredient(stepIndex, ingIndex, 1), { className: "aisle-icon--flipped btn-move-down", label: "Move down" })
    if (ingIndex >= total - 1) downBtn.disabled = true
    actions.appendChild(downBtn)
    actions.appendChild(buildIconButton("delete", () => this.removeIngredient(stepIndex, ingIndex), { className: "btn-danger", label: "Remove" }))
    card.appendChild(actions)

    return card
  }

  addIngredient(stepIndex) {
    if (!this.steps[stepIndex].ingredients) this.steps[stepIndex].ingredients = []
    this.steps[stepIndex].ingredients.unshift({ name: "", quantity: "", prep_note: "" })
    this.rebuildIngredientRows(stepIndex)
  }

  removeIngredient(stepIndex, ingIndex) {
    removeFromList(this.steps[stepIndex].ingredients, ingIndex, () => this.rebuildIngredientRows(stepIndex))
  }

  moveIngredient(stepIndex, ingIndex, direction) {
    const container = this.stepsContainerTarget
      .querySelector(`.graphical-ingredient-rows[data-step-index="${stepIndex}"]`)
    moveInList(this.steps[stepIndex].ingredients, ingIndex, direction, container, () => this.rebuildIngredientRows(stepIndex))
  }

  rebuildIngredientRows(stepIndex) {
    const container = this.stepsContainerTarget
      .querySelector(`.graphical-ingredient-rows[data-step-index="${stepIndex}"]`)
    if (!container) return
    rebuildContainer(container, this.steps[stepIndex].ingredients || [],
      (i, ing) => this.buildIngredientRow(stepIndex, i, ing))
    updateMoveButtons(container)
  }

  // --- Serialization ---

  serializeSteps() {
    return this.steps.map(step => {
      if (step.cross_reference) return { ...step }
      return {
        tldr: step.tldr || null,
        ingredients: this.serializeIngredients(step.ingredients),
        instructions: step.instructions?.trim() || null,
        cross_reference: null
      }
    })
  }

  serializeIngredients(ingredients) {
    if (!ingredients) return []
    return ingredients
      .filter(ing => ing.name && ing.name.trim() !== "")
      .map(ing => ({
        name: ing.name.trim(),
        quantity: ing.quantity?.trim() || null,
        prep_note: ing.prep_note?.trim() || null
      }))
  }

  emptyStep() {
    return { tldr: "", ingredients: [], instructions: "", cross_reference: null }
  }
}
