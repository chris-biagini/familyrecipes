document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.editor-dialog').forEach(initEditor);

  // Cross-reference toast (recipe-specific, fires once on page load)
  const params = new URLSearchParams(window.location.search);
  const refsUpdated = params.get('refs_updated');
  if (refsUpdated && typeof Notify !== 'undefined') {
    Notify.show(`Updated references in ${refsUpdated}.`);
    const cleanUrl = window.location.pathname + window.location.hash;
    history.replaceState(null, '', cleanUrl);
  }
});

function initEditor(dialog) {
  const openSelector = dialog.dataset.editorOpen;
  const openBtn = openSelector ? document.querySelector(openSelector) : null;
  const closeBtn = dialog.querySelector('.editor-close');
  const cancelBtn = dialog.querySelector('.editor-cancel');
  const saveBtn = dialog.querySelector('.editor-save');
  const deleteBtn = dialog.querySelector('.editor-delete');
  const textarea = dialog.querySelector('.editor-textarea');
  const errorsDiv = dialog.querySelector('.editor-errors');
  const actionUrl = dialog.dataset.editorUrl;
  const method = dialog.dataset.editorMethod || 'PATCH';
  const onSuccess = dialog.dataset.editorOnSuccess || 'redirect';
  const bodyKey = dialog.dataset.editorBodyKey || 'markdown_source';

  if (!openBtn || !textarea) return;

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

  openBtn.addEventListener('click', () => {
    clearErrors();

    const loadUrl = dialog.dataset.editorLoadUrl;
    if (loadUrl) {
      textarea.value = '';
      textarea.disabled = true;
      textarea.placeholder = 'Loading\u2026';
      dialog.showModal();

      fetch(loadUrl, {
        headers: { 'Accept': 'application/json', 'X-CSRF-Token': csrfToken }
      })
        .then(response => response.json())
        .then(data => {
          const key = dialog.dataset.editorLoadKey || 'content';
          textarea.value = data[key] || '';
          originalContent = textarea.value;
          textarea.disabled = false;
          textarea.placeholder = '';
          textarea.focus();
        })
        .catch(() => {
          textarea.value = '';
          textarea.disabled = false;
          textarea.placeholder = '';
          showErrors(['Failed to load content. Close and try again.']);
        });
    } else {
      originalContent = textarea.value;
      dialog.showModal();
    }
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
      const response = await fetch(actionUrl, {
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ [bodyKey]: textarea.value })
      });

      if (response.ok) {
        const data = await response.json();
        saving = true;

        if (onSuccess === 'reload') {
          window.location.reload();
        } else {
          let redirectUrl = data.redirect_url;
          if (data.updated_references?.length > 0) {
            const param = encodeURIComponent(data.updated_references.join(', '));
            const separator = redirectUrl.includes('?') ? '&' : '?';
            redirectUrl += `${separator}refs_updated=${param}`;
          }
          window.location = redirectUrl;
        }
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

  // Delete (recipe editor only)
  if (deleteBtn) {
    deleteBtn.addEventListener('click', async () => {
      const title = deleteBtn.dataset.recipeTitle;
      const slug = deleteBtn.dataset.recipeSlug;
      const referencing = JSON.parse(deleteBtn.dataset.referencingRecipes || '[]');

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
        const response = await fetch(actionUrl, {
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
}
