import { Controller } from "@hotwired/stimulus"

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
    "categorySelect", "categoryInput",
    "stepsContainer", "footer"
  ]

  connect() {
    this.steps = []
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
    return JSON.stringify(this.toStructure()) !== JSON.stringify(original)
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
    if (this.hasCategoryInputTarget) {
      this.categoryInputTarget.value = value || ""
      this.categoryInputTarget.hidden = false
      this.categorySelectTarget.hidden = true
    }
  }

  categoryChanged() {
    if (!this.hasCategoryInputTarget) return
    if (this.categorySelectTarget.value === "__new__") {
      this.categoryInputTarget.hidden = false
      this.categorySelectTarget.hidden = true
      this.categoryInputTarget.focus()
    }
  }

  categoryInputKeydown(event) {
    if (event.key !== "Escape") return
    this.categoryInputTarget.hidden = true
    this.categorySelectTarget.hidden = false
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
    if (this.steps.length > 0) this.expandStep(0)
  }

  removeStep(index) {
    if (this.steps.length <= 1) return
    this.steps.splice(index, 1)
    this.rebuildSteps()
  }

  moveStep(index, direction) {
    const target = index + direction
    if (target < 0 || target >= this.steps.length) return

    const [moved] = this.steps.splice(index, 1)
    this.steps.splice(target, 0, moved)
    this.rebuildSteps()
    this.expandStep(target)
  }

  rebuildSteps() {
    this.stepsContainerTarget.replaceChildren()
    this.steps.forEach((step, i) => this.appendStepCard(i, step))
  }

  appendStepCard(index, stepData) {
    const card = this.buildStepCard(index, stepData)
    this.stepsContainerTarget.appendChild(card)
  }

  toggleStep(index) {
    const card = this.stepsContainerTarget.children[index]
    if (!card) return
    const body = card.querySelector(".graphical-step-body")
    const icon = card.querySelector(".graphical-step-toggle-icon")
    if (!body) return

    const isHidden = body.hidden
    body.hidden = !isHidden
    if (icon) icon.textContent = isHidden ? "\u25BC" : "\u25B6"
  }

  expandStep(index) {
    this.collapseAllSteps()
    this.toggleStep(index)
  }

  collapseAllSteps() {
    const cards = this.stepsContainerTarget.children
    for (let i = 0; i < cards.length; i++) {
      const body = cards[i].querySelector(".graphical-step-body")
      const icon = cards[i].querySelector(".graphical-step-toggle-icon")
      if (body) body.hidden = true
      if (icon) icon.textContent = "\u25B6"
    }
  }

  findExpandedIndex() {
    const cards = this.stepsContainerTarget.children
    for (let i = 0; i < cards.length; i++) {
      const body = cards[i].querySelector(".graphical-step-body")
      if (body && !body.hidden) return i
    }
    return -1
  }

  // --- Step Card DOM Builder ---

  buildStepCard(index, stepData) {
    if (stepData.cross_reference) return this.buildCrossRefCard(index, stepData)

    const card = document.createElement("div")
    card.className = "graphical-step-card"
    card.appendChild(this.buildStepHeader(index, stepData))
    card.appendChild(this.buildStepBody(index, stepData))
    return card
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

    header.appendChild(this.buildStepActions(index))
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

  buildStepHeader(index, stepData) {
    const header = document.createElement("div")
    header.className = "graphical-step-header"
    header.addEventListener("click", (e) => {
      if (e.target.closest(".graphical-step-actions") || e.target.closest(".graphical-step-toggle")) return
      this.toggleStep(index)
    })

    header.appendChild(this.buildToggleButton(index))
    header.appendChild(this.buildStepTitle(index, stepData))
    header.appendChild(this.buildIngredientSummary(stepData))
    header.appendChild(this.buildStepActions(index))
    return header
  }

  buildToggleButton(index) {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "graphical-step-toggle"
    const icon = document.createElement("span")
    icon.className = "graphical-step-toggle-icon"
    icon.textContent = "\u25B6"
    btn.appendChild(icon)
    btn.addEventListener("click", () => this.toggleStep(index))
    return btn
  }

  buildStepTitle(index, stepData) {
    const span = document.createElement("span")
    span.className = "graphical-step-title"
    span.textContent = stepData.tldr || `Step ${index + 1}`
    return span
  }

  buildIngredientSummary(stepData) {
    const span = document.createElement("span")
    span.className = "graphical-ingredient-summary"
    const count = (stepData.ingredients || []).length
    span.textContent = count === 0 ? "" : `${count} ingredient${count === 1 ? "" : "s"}`
    return span
  }

  buildStepActions(index) {
    const actions = document.createElement("div")
    actions.className = "graphical-step-actions"

    actions.appendChild(this.buildButton("\u2191", () => this.moveStep(index, -1), "graphical-btn--icon"))
    actions.appendChild(this.buildButton("\u2193", () => this.moveStep(index, 1), "graphical-btn--icon"))
    actions.appendChild(this.buildButton("\u00D7", () => this.removeStep(index), "graphical-btn--icon graphical-btn--danger"))
    return actions
  }

  buildStepBody(index, stepData) {
    const body = document.createElement("div")
    body.className = "graphical-step-body"
    body.hidden = true

    body.appendChild(this.buildFieldGroup("Step name", "text", stepData.tldr || "", (val) => {
      this.steps[index].tldr = val
      this.updateStepTitleDisplay(index)
    }))

    body.appendChild(this.buildIngredientsSection(index, stepData.ingredients || []))

    body.appendChild(this.buildTextareaGroup("Instructions", stepData.instructions || "", (val) => {
      this.steps[index].instructions = val
    }))

    return body
  }

  updateStepTitleDisplay(index) {
    const card = this.stepsContainerTarget.children[index]
    if (!card) return
    const titleEl = card.querySelector(".graphical-step-title")
    if (titleEl) titleEl.textContent = this.steps[index].tldr || `Step ${index + 1}`
  }

  // --- Ingredient Rows ---

  buildIngredientsSection(stepIndex, ingredients) {
    const section = document.createElement("div")
    section.className = "graphical-ingredients-section"

    const headerRow = document.createElement("div")
    headerRow.className = "graphical-ingredients-header"

    const label = document.createElement("span")
    label.textContent = "Ingredients"
    headerRow.appendChild(label)

    headerRow.appendChild(this.buildButton("+ Add", () => this.addIngredient(stepIndex), "graphical-btn--small"))

    section.appendChild(headerRow)

    const rowsContainer = document.createElement("div")
    rowsContainer.className = "graphical-ingredient-rows"
    rowsContainer.dataset.stepIndex = stepIndex
    ingredients.forEach((ing, i) => {
      rowsContainer.appendChild(this.buildIngredientRow(stepIndex, i, ing))
    })
    section.appendChild(rowsContainer)

    return section
  }

  buildIngredientRow(stepIndex, ingIndex, ing) {
    const row = document.createElement("div")
    row.className = "graphical-ingredient-row"

    row.appendChild(this.buildInput("Name", ing.name || "", (val) => {
      this.steps[stepIndex].ingredients[ingIndex].name = val
    }, "graphical-input--name"))

    row.appendChild(this.buildInput("Qty", ing.quantity || "", (val) => {
      this.steps[stepIndex].ingredients[ingIndex].quantity = val
    }, "graphical-input--qty"))

    row.appendChild(this.buildInput("Prep note", ing.prep_note || "", (val) => {
      this.steps[stepIndex].ingredients[ingIndex].prep_note = val
    }, "graphical-input--prep"))

    const actions = document.createElement("div")
    actions.className = "graphical-ingredient-actions"
    actions.appendChild(this.buildButton("\u2191", () => this.moveIngredient(stepIndex, ingIndex, -1), "graphical-btn--icon"))
    actions.appendChild(this.buildButton("\u2193", () => this.moveIngredient(stepIndex, ingIndex, 1), "graphical-btn--icon"))
    actions.appendChild(this.buildButton("\u00D7", () => this.removeIngredient(stepIndex, ingIndex), "graphical-btn--icon graphical-btn--danger"))
    row.appendChild(actions)

    return row
  }

  addIngredient(stepIndex) {
    if (!this.steps[stepIndex].ingredients) this.steps[stepIndex].ingredients = []
    this.steps[stepIndex].ingredients.push({ name: "", quantity: "", prep_note: "" })
    this.rebuildIngredientRows(stepIndex)
  }

  removeIngredient(stepIndex, ingIndex) {
    this.steps[stepIndex].ingredients.splice(ingIndex, 1)
    this.rebuildIngredientRows(stepIndex)
  }

  moveIngredient(stepIndex, ingIndex, direction) {
    const ings = this.steps[stepIndex].ingredients
    const target = ingIndex + direction
    if (target < 0 || target >= ings.length) return

    const [moved] = ings.splice(ingIndex, 1)
    ings.splice(target, 0, moved)
    this.rebuildIngredientRows(stepIndex)
  }

  rebuildIngredientRows(stepIndex) {
    const container = this.stepsContainerTarget
      .querySelector(`.graphical-ingredient-rows[data-step-index="${stepIndex}"]`)
    if (!container) return

    container.replaceChildren()
    const ings = this.steps[stepIndex].ingredients || []
    ings.forEach((ing, i) => {
      container.appendChild(this.buildIngredientRow(stepIndex, i, ing))
    })
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

  // --- DOM Builder Helpers ---

  emptyStep() {
    return { tldr: "", ingredients: [], instructions: "", cross_reference: null }
  }

  buildButton(text, onClick, className) {
    const btn = document.createElement("button")
    btn.type = "button"
    if (className) btn.className = className
    btn.textContent = text
    btn.addEventListener("click", onClick)
    return btn
  }

  buildInput(placeholder, value, onChange, className) {
    const input = document.createElement("input")
    input.type = "text"
    input.placeholder = placeholder
    input.value = value
    if (className) input.className = className
    input.addEventListener("input", () => onChange(input.value))
    return input
  }

  buildFieldGroup(labelText, type, value, onChange) {
    const group = document.createElement("div")
    group.className = "graphical-field-group"

    const label = document.createElement("label")
    label.textContent = labelText
    group.appendChild(label)

    const input = document.createElement("input")
    input.type = type
    input.value = value
    input.addEventListener("input", () => onChange(input.value))
    group.appendChild(input)

    return group
  }

  buildTextareaGroup(labelText, value, onChange) {
    const group = document.createElement("div")
    group.className = "graphical-field-group"

    const label = document.createElement("label")
    label.textContent = labelText
    group.appendChild(label)

    const textarea = document.createElement("textarea")
    textarea.value = value
    textarea.rows = 4
    textarea.addEventListener("input", () => onChange(textarea.value))
    group.appendChild(textarea)

    return group
  }
}
