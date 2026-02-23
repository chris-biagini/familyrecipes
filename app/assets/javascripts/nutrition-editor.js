document.addEventListener('DOMContentLoaded', () => {
  const dialog = document.getElementById('nutrition-editor');
  if (!dialog) return;

  const textarea = document.getElementById('nutrition-editor-textarea');
  const titleEl = document.getElementById('nutrition-editor-title');
  const closeBtn = dialog.querySelector('.editor-close');
  const cancelBtn = dialog.querySelector('.editor-cancel');
  const saveBtn = dialog.querySelector('.editor-save');
  const errorsDiv = dialog.querySelector('.editor-errors');
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;

  let currentIngredient = null;
  let originalContent = '';
  let saving = false;

  function isModified() {
    return textarea.value !== originalContent;
  }

  function showErrors(errors) {
    const list = document.createElement('ul');
    errors.forEach(msg => {
      const li = document.createElement('li');
      li.textContent = msg;
      list.appendChild(li);
    });
    errorsDiv.replaceChildren(list);
    errorsDiv.hidden = false;
  }

  function clearErrors() {
    errorsDiv.replaceChildren();
    errorsDiv.hidden = true;
  }

  function closeDialog() {
    if (isModified() && !confirm('You have unsaved changes. Discard them?')) return;
    textarea.value = originalContent;
    clearErrors();
    dialog.close();
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

  // Open from edit/add buttons
  document.querySelectorAll('.nutrition-edit-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      currentIngredient = btn.dataset.ingredient;
      textarea.value = btn.dataset.nutritionText;
      originalContent = textarea.value;
      titleEl.textContent = currentIngredient;
      clearErrors();
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
          headers: { 'X-CSRF-Token': csrfToken }
        });

        if (response.ok) {
          saving = true;
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
  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving\u2026';
    clearErrors();

    try {
      const response = await fetch(nutritionUrl(currentIngredient), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ label_text: textarea.value })
      });

      if (response.ok) {
        saving = true;
        window.location.reload();
      } else if (response.status === 422) {
        const data = await response.json();
        showErrors(data.errors);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      } else {
        showErrors(['Server error (' + response.status + '). Please try again.']);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      }
    } catch {
      showErrors(['Network error. Please check your connection and try again.']);
      saveBtn.disabled = false;
      saveBtn.textContent = 'Save';
    }
  });

  // Warn on navigation with unsaved changes
  window.addEventListener('beforeunload', (event) => {
    if (!saving && dialog.open && isModified()) {
      event.preventDefault();
    }
  });
});
