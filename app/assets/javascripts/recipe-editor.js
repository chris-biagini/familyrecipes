document.addEventListener('DOMContentLoaded', () => {
  const dialog = document.getElementById('recipe-editor');
  const editBtn = document.getElementById('edit-button');
  const closeBtn = document.getElementById('editor-close');
  const cancelBtn = document.getElementById('editor-cancel');
  const saveBtn = document.getElementById('editor-save');
  const textarea = document.getElementById('editor-textarea');
  const errorsDiv = document.getElementById('editor-errors');

  if (!dialog || !editBtn) return;

  const recipeSlug = document.body.dataset.recipeId;
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
  let originalContent = textarea.value;
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
    if (isModified() && !confirm('You have unsaved changes. Discard them?')) {
      return;
    }
    textarea.value = originalContent;
    clearErrors();
    dialog.close();
  }

  // Open
  editBtn.addEventListener('click', () => {
    originalContent = textarea.value;
    clearErrors();
    dialog.showModal();
  });

  // Close buttons
  closeBtn.addEventListener('click', closeDialog);
  cancelBtn.addEventListener('click', closeDialog);

  // Escape key — intercept to check for unsaved changes
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
      const response = await fetch(`/recipes/${recipeSlug}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ markdown_source: textarea.value })
      });

      if (response.ok) {
        const data = await response.json();
        saving = true;
        window.location = data.redirect_url;
      } else if (response.status === 422) {
        const data = await response.json();
        showErrors(data.errors);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      } else {
        showErrors([`Server error (${response.status}). Please try again.`]);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      }
    } catch {
      showErrors(['Network error. Please check your connection and try again.']);
      saveBtn.disabled = false;
      saveBtn.textContent = 'Save';
    }
  });

  // Warn on page navigation with unsaved changes
  window.addEventListener('beforeunload', (event) => {
    if (!saving && dialog.open && isModified()) {
      event.preventDefault();
    }
  });
});
