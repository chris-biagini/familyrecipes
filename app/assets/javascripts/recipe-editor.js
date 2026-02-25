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

  let originalContent = textarea.value;

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

  const guard = EditorUtils.guardBeforeUnload(dialog, isModified);

  openBtn.addEventListener('click', () => {
    EditorUtils.clearErrors(errorsDiv);

    const loadUrl = dialog.dataset.editorLoadUrl;
    if (loadUrl) {
      textarea.value = '';
      textarea.disabled = true;
      textarea.placeholder = 'Loading\u2026';
      dialog.showModal();

      fetch(loadUrl, {
        headers: { 'Accept': 'application/json', 'X-CSRF-Token': EditorUtils.getCsrfToken() }
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
          EditorUtils.showErrors(errorsDiv, ['Failed to load content. Close and try again.']);
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
  saveBtn.addEventListener('click', () => {
    EditorUtils.handleSave(
      saveBtn,
      errorsDiv,
      () => EditorUtils.saveRequest(actionUrl, method, { [bodyKey]: textarea.value }),
      (data) => {
        guard.markSaving();

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
      }
    );
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
            'X-CSRF-Token': EditorUtils.getCsrfToken()
          }
        });

        if (response.ok) {
          const data = await response.json();
          guard.markSaving();
          window.location = data.redirect_url;
        } else {
          EditorUtils.showErrors(errorsDiv, [`Failed to delete (${response.status}). Please try again.`]);
          deleteBtn.disabled = false;
          deleteBtn.textContent = 'Delete';
        }
      } catch {
        EditorUtils.showErrors(errorsDiv, ['Network error. Please check your connection and try again.']);
        deleteBtn.disabled = false;
        deleteBtn.textContent = 'Delete';
      }
    });
  }
}
