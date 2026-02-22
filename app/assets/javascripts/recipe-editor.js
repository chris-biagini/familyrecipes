document.addEventListener('DOMContentLoaded', () => {
  const dialog = document.getElementById('recipe-editor');
  if (!dialog) return;

  const mode = dialog.dataset.editorMode;
  const actionUrl = dialog.dataset.editorUrl;
  const openBtn = mode === 'create'
    ? document.getElementById('new-recipe-button')
    : document.getElementById('edit-button');
  const closeBtn = document.getElementById('editor-close');
  const cancelBtn = document.getElementById('editor-cancel');
  const saveBtn = document.getElementById('editor-save');
  const deleteBtn = document.getElementById('editor-delete');
  const textarea = document.getElementById('editor-textarea');
  const errorsDiv = document.getElementById('editor-errors');

  if (!openBtn) return;

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
  openBtn.addEventListener('click', () => {
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

  // Save (create or update)
  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving\u2026';
    clearErrors();

    const method = mode === 'create' ? 'POST' : 'PATCH';

    try {
      const response = await fetch(actionUrl, {
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ markdown_source: textarea.value })
      });

      if (response.ok) {
        const data = await response.json();
        saving = true;

        let redirectUrl = data.redirect_url;
        if (data.updated_references && data.updated_references.length > 0) {
          const param = encodeURIComponent(data.updated_references.join(', '));
          const separator = redirectUrl.includes('?') ? '&' : '?';
          redirectUrl += `${separator}refs_updated=${param}`;
        }
        window.location = redirectUrl;
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

  // Delete (edit mode only)
  if (deleteBtn) {
    deleteBtn.addEventListener('click', async () => {
      const title = deleteBtn.dataset.recipeTitle;
      const slug = deleteBtn.dataset.recipeSlug;
      const referencingRaw = deleteBtn.dataset.referencingRecipes;
      const referencing = JSON.parse(referencingRaw || '[]');

      let message;
      if (referencing.length > 0) {
        message = `Delete "${title}"?\n\nCross-references in ${referencing.join(', ')} will be converted to plain text.\n\nThis cannot be undone.`;
      } else {
        message = `Delete "${title}"?\n\nThis cannot be undone.`;
      }

      if (!confirm(message)) return;

      deleteBtn.disabled = true;
      deleteBtn.textContent = 'Deleting\u2026';

      try {
        const response = await fetch(`/recipes/${slug}`, {
          method: 'DELETE',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrfToken
          }
        });

        if (response.ok) {
          const data = await response.json();
          saving = true;
          window.location = data.redirect_url;
        } else {
          showErrors([`Failed to delete (${response.status}). Please try again.`]);
          deleteBtn.disabled = false;
          deleteBtn.textContent = 'Delete';
        }
      } catch {
        showErrors(['Network error. Please check your connection and try again.']);
        deleteBtn.disabled = false;
        deleteBtn.textContent = 'Delete';
      }
    });
  }

  // Warn on page navigation with unsaved changes
  window.addEventListener('beforeunload', (event) => {
    if (!saving && dialog.open && isModified()) {
      event.preventDefault();
    }
  });

  // Show toast for cross-reference updates (from URL param)
  const params = new URLSearchParams(window.location.search);
  const refsUpdated = params.get('refs_updated');
  if (refsUpdated && typeof Notify !== 'undefined') {
    Notify.show(`Updated references in ${refsUpdated}.`);
    const cleanUrl = window.location.pathname + window.location.hash;
    history.replaceState(null, '', cleanUrl);
  }
});
