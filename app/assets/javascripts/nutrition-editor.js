document.addEventListener('DOMContentLoaded', () => {
  const dialog = document.getElementById('nutrition-editor');
  if (!dialog) return;

  const textarea = document.getElementById('nutrition-editor-textarea');
  const titleEl = document.getElementById('nutrition-editor-title');
  const closeBtn = dialog.querySelector('.editor-close');
  const cancelBtn = dialog.querySelector('.editor-cancel');
  const saveBtn = dialog.querySelector('.editor-save');
  const errorsDiv = dialog.querySelector('.editor-errors');
  const aisleSelect = document.getElementById('nutrition-editor-aisle');
  const aisleInput = document.getElementById('nutrition-editor-aisle-input');

  let currentIngredient = null;
  let originalContent = '';
  let originalAisle = '';

  function currentAisle() {
    return aisleInput.hidden ? aisleSelect.value : aisleInput.value.trim();
  }

  function isModified() {
    return textarea.value !== originalContent || currentAisle() !== originalAisle;
  }

  function resetDialog() {
    textarea.value = originalContent;
    aisleSelect.value = originalAisle || '';
    aisleSelect.hidden = false;
    aisleInput.hidden = true;
    aisleInput.value = '';
    EditorUtils.clearErrors(errorsDiv);
  }

  function closeDialog() {
    EditorUtils.closeWithConfirmation(dialog, isModified, resetDialog);
  }

  // Build the nutrition URL from the ingredient name.
  // The page URL is like /kitchens/slug/index
  // The nutrition URL is /kitchens/slug/nutrition/Ingredient-Name
  function nutritionUrl(name) {
    const slug = name.replace(/ /g, '-');
    const parts = window.location.pathname.split('/');
    const kitchensIdx = parts.indexOf('kitchens');
    const base = parts.slice(0, kitchensIdx + 2).join('/');
    return base + '/nutrition/' + encodeURIComponent(slug);
  }

  const guard = EditorUtils.guardBeforeUnload(dialog, isModified);

  // Open from edit/add buttons
  document.querySelectorAll('.nutrition-edit-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      currentIngredient = btn.dataset.ingredient;
      textarea.value = btn.dataset.nutritionText;
      originalContent = textarea.value;
      originalAisle = btn.dataset.aisle || '';
      aisleSelect.value = originalAisle;
      // If the value wasn't found in the select options, reset to empty
      if (aisleSelect.value !== originalAisle) aisleSelect.value = '';
      aisleInput.hidden = true;
      aisleInput.value = '';
      aisleSelect.hidden = false;
      titleEl.textContent = currentIngredient;
      EditorUtils.clearErrors(errorsDiv);
      dialog.showModal();
    });
  });

  // "Other..." handling for aisle select
  aisleSelect.addEventListener('change', () => {
    if (aisleSelect.value === '__other__') {
      aisleSelect.hidden = true;
      aisleInput.hidden = false;
      aisleInput.value = '';
      aisleInput.focus();
    }
  });

  aisleInput.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      aisleInput.hidden = true;
      aisleSelect.hidden = false;
      aisleSelect.value = originalAisle || '';
    }
  });

  // Reset buttons (delete kitchen override)
  document.querySelectorAll('.nutrition-reset-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      const name = btn.dataset.ingredient;
      if (!confirm('Reset "' + name + '" to built-in nutrition data?')) return;

      btn.disabled = true;
      try {
        const response = await fetch(nutritionUrl(name), {
          method: 'DELETE',
          headers: { 'X-CSRF-Token': EditorUtils.getCsrfToken() }
        });

        if (response.ok) {
          guard.markSaving();
          window.location.reload();
        } else {
          btn.disabled = false;
          alert('Failed to reset. Please try again.');
        }
      } catch {
        btn.disabled = false;
        alert('Network error. Please try again.');
      }
    });
  });

  closeBtn.addEventListener('click', closeDialog);
  cancelBtn.addEventListener('click', closeDialog);

  dialog.addEventListener('cancel', (event) => {
    if (isModified()) {
      event.preventDefault();
      closeDialog();
    }
  });

  // Save
  saveBtn.addEventListener('click', () => {
    EditorUtils.handleSave(
      saveBtn,
      errorsDiv,
      () => {
        const nutritionChanged = textarea.value !== originalContent;
        return EditorUtils.saveRequest(nutritionUrl(currentIngredient), 'POST', {
          label_text: nutritionChanged ? textarea.value : '',
          aisle: currentAisle()
        });
      },
      () => {
        guard.markSaving();
        window.location.reload();
      }
    );
  });
});
