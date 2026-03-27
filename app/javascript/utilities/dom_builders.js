/**
 * Shared DOM factory functions for graphical editors. Pure element
 * creators with no Stimulus or framework coupling.
 *
 * - icons: SVG icon builder (buildIcon) for icon buttons
 * - graphical_editor_utils: higher-level card/section builders
 * - recipe_graphical_controller: recipe step/ingredient editing
 * - quickbites_graphical_controller: category/item editing
 */

import { buildIcon } from "./icons"

export function buildIconButton(iconName, onClick, { className = "", label = "", size = 14 } = {}) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.className = `btn-icon-round ${className}`.trim()
  if (label) btn.setAttribute("aria-label", label)
  btn.appendChild(buildIcon(iconName, size))
  btn.addEventListener("click", onClick)
  return btn
}

export function buildPillButton(text, onClick, className) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.className = className ? `btn-pill ${className}` : "btn-pill"
  btn.textContent = text
  btn.addEventListener("click", onClick)
  return btn
}

export function buildInput(placeholder, value, onChange, className) {
  const input = document.createElement("input")
  input.type = "text"
  input.placeholder = placeholder
  input.value = value
  input.className = className ? `input-base ${className}` : "input-base"
  input.addEventListener("input", () => onChange(input.value))
  return input
}

export function buildFieldGroup(labelText, type, value, onChange) {
  const group = document.createElement("div")
  group.className = "graphical-field-group"

  const label = document.createElement("label")
  label.textContent = labelText
  group.appendChild(label)

  const input = document.createElement("input")
  input.type = type
  input.className = "input-base"
  input.value = value
  input.addEventListener("input", () => onChange(input.value))
  group.appendChild(input)

  return group
}

export function buildTextareaGroup(labelText, value, onChange) {
  const group = document.createElement("div")
  group.className = "graphical-field-group"

  const label = document.createElement("label")
  label.textContent = labelText
  group.appendChild(label)

  const textarea = document.createElement("textarea")
  textarea.className = "input-base"
  textarea.value = value
  textarea.rows = 4
  textarea.addEventListener("input", () => onChange(textarea.value))
  group.appendChild(textarea)

  return group
}
