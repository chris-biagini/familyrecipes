document.addEventListener('DOMContentLoaded', () => {
  const dialog = document.getElementById('nutrition-editor');
  if (!dialog) return;

  const textarea = document.getElementById('nutrition-editor-textarea');
  const titleEl = document.getElementById('nutrition-editor-title');
  const closeBtn = dialog.querySelector('.editor-close');
  const cancelBtn = dialog.querySelector('.editor-cancel');
  const saveBtn = dialog.querySelector('.editor-save');
  const errorsDiv = dialog.querySelector('.editor-errors');

  let currentIngredient = null;
  let originalContent = '';

  function isModified() {
    return textarea.value !== originalContent;
  }

  function resetDialog() {
    textarea.value = originalContent;
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
      titleEl.textContent = currentIngredient;
      EditorUtils.clearErrors(errorsDiv);
      dialog.showModal();
    });
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
      () => EditorUtils.saveRequest(nutritionUrl(currentIngredient), 'POST', { label_text: textarea.value }),
      () => {
        guard.markSaving();
        window.location.reload();
      }
    );
  });
});
