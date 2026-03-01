/**
 * Shared utilities for editor dialogs: CSRF token extraction, error display/clear,
 * close-with-confirmation, beforeunload guard, and a generic save-request handler.
 * Used by editor_controller and nutrition_editor_controller to avoid duplicating
 * fetch boilerplate and UI state management.
 */
export function getCsrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

export function showErrors(container, errors) {
  const list = document.createElement('ul')
  errors.forEach(msg => {
    const li = document.createElement('li')
    li.textContent = msg
    list.appendChild(li)
  })
  container.replaceChildren(list)
  container.hidden = false
}

export function clearErrors(container) {
  container.replaceChildren()
  container.hidden = true
}

export function closeWithConfirmation(dialog, isModified, resetFn) {
  if (isModified() && !confirm('You have unsaved changes. Discard them?')) return
  resetFn()
  dialog.close()
}

export async function saveRequest(url, method, body) {
  return fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': getCsrfToken()
    },
    body: JSON.stringify(body)
  })
}

export function guardBeforeUnload(dialog, isModified) {
  let saving = false

  function handler(event) {
    if (!saving && dialog.open && isModified()) {
      event.preventDefault()
    }
  }

  window.addEventListener('beforeunload', handler)

  return {
    markSaving() { saving = true },
    remove() { window.removeEventListener('beforeunload', handler) }
  }
}

export async function handleSave(saveBtn, errorsDiv, saveFn, onSuccess) {
  saveBtn.disabled = true
  saveBtn.textContent = 'Saving\u2026'
  clearErrors(errorsDiv)

  try {
    const response = await saveFn()

    if (response.ok) {
      onSuccess(await response.json())
    } else if (response.status === 422) {
      const data = await response.json()
      showErrors(errorsDiv, data.errors)
      saveBtn.disabled = false
      saveBtn.textContent = 'Save'
    } else {
      showErrors(errorsDiv, [`Server error (${response.status}). Please try again.`])
      saveBtn.disabled = false
      saveBtn.textContent = 'Save'
    }
  } catch {
    showErrors(errorsDiv, ['Network error. Please check your connection and try again.'])
    saveBtn.disabled = false
    saveBtn.textContent = 'Save'
  }
}
