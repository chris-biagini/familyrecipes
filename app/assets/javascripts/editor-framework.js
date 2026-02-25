// Unified editor dialog framework.
// Auto-discovers .editor-dialog elements and manages lifecycle via custom DOM events.
// Simple dialogs: configure entirely with data-editor-* attributes (no custom JS).
// Custom dialogs: listen for editor:* events on the dialog element and set detail.handled = true.
//
// Events dispatched on <dialog>:
//   editor:collect  — Save clicked.    detail: { handled, data }
//   editor:save     — After collect.   detail: { handled, data, saveFn }
//   editor:modified — Dirty-check.     detail: { handled, modified }
//   editor:reset    — Cancel/close.    detail: { handled }
//
// Depends on: editor-utils.js (must load first)

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.editor-dialog').forEach(initEditor);

  const params = new URLSearchParams(window.location.search);
  const refsUpdated = params.get('refs_updated');
  if (refsUpdated && typeof Notify !== 'undefined') {
    Notify.show(`Updated references in ${refsUpdated}.`);
    const cleanUrl = window.location.pathname + window.location.hash;
    history.replaceState(null, '', cleanUrl);
  }
});

function initEditor(dialog) {
  const closeBtn = dialog.querySelector('.editor-close');
  const cancelBtn = dialog.querySelector('.editor-cancel');
  const saveBtn = dialog.querySelector('.editor-save');
  const deleteBtn = dialog.querySelector('.editor-delete');
  const textarea = dialog.querySelector('.editor-textarea');
  const errorsDiv = dialog.querySelector('.editor-errors');

  const openSelector = dialog.dataset.editorOpen;
  const actionUrl = dialog.dataset.editorUrl;
  const method = dialog.dataset.editorMethod || 'PATCH';
  const onSuccess = dialog.dataset.editorOnSuccess || 'redirect';
  const bodyKey = dialog.dataset.editorBodyKey || 'markdown_source';

  let originalContent = '';

  // --- Event helpers ---

  function dispatch(name, extra) {
    const detail = Object.assign({ handled: false }, extra);
    const event = new CustomEvent(name, { detail: detail, bubbles: false });
    dialog.dispatchEvent(event);
    return event.detail;
  }

  function isModified() {
    const result = dispatch('editor:modified', { modified: false });
    if (result.handled) return result.modified;
    return textarea ? textarea.value !== originalContent : false;
  }

  function resetContent() {
    const result = dispatch('editor:reset');
    if (!result.handled && textarea) textarea.value = originalContent;
    EditorUtils.clearErrors(errorsDiv);
  }

  function closeDialog() {
    EditorUtils.closeWithConfirmation(dialog, isModified, resetContent);
  }

  const guard = EditorUtils.guardBeforeUnload(dialog, isModified);

  // --- Open trigger (default behavior, skipped for custom dialogs without data-editor-open) ---

  if (openSelector) {
    const openBtn = document.querySelector(openSelector);
    if (openBtn) {
      openBtn.addEventListener('click', () => {
        EditorUtils.clearErrors(errorsDiv);

        const loadUrl = dialog.dataset.editorLoadUrl;
        if (loadUrl) {
          if (textarea) {
            textarea.value = '';
            textarea.disabled = true;
            textarea.placeholder = 'Loading\u2026';
          }
          dialog.showModal();

          fetch(loadUrl, {
            headers: { 'Accept': 'application/json', 'X-CSRF-Token': EditorUtils.getCsrfToken() }
          })
            .then(function(r) { return r.json(); })
            .then(function(data) {
              var key = dialog.dataset.editorLoadKey || 'content';
              if (textarea) {
                textarea.value = data[key] || '';
                originalContent = textarea.value;
                textarea.disabled = false;
                textarea.placeholder = '';
                textarea.focus();
              }
            })
            .catch(function() {
              if (textarea) {
                textarea.value = '';
                textarea.disabled = false;
                textarea.placeholder = '';
              }
              EditorUtils.showErrors(errorsDiv, ['Failed to load content. Close and try again.']);
            });
        } else {
          if (textarea) originalContent = textarea.value;
          dialog.showModal();
        }
      });
    }
  }

  // --- Close / Cancel ---

  if (closeBtn) closeBtn.addEventListener('click', closeDialog);
  if (cancelBtn) cancelBtn.addEventListener('click', closeDialog);

  dialog.addEventListener('cancel', function(event) {
    if (isModified()) {
      event.preventDefault();
      closeDialog();
    }
  });

  // --- Save ---

  if (saveBtn) {
    saveBtn.addEventListener('click', function() {
      var collectResult = dispatch('editor:collect', { data: null });
      var data = collectResult.handled ? collectResult.data : { [bodyKey]: textarea?.value };

      var saveResult = dispatch('editor:save', { data: data, saveFn: null });
      var saveFn = saveResult.handled && saveResult.saveFn
        ? saveResult.saveFn
        : function() { return EditorUtils.saveRequest(actionUrl, method, data); };

      EditorUtils.handleSave(saveBtn, errorsDiv, saveFn, function(responseData) {
        guard.markSaving();

        if (onSuccess === 'reload') {
          window.location.reload();
        } else {
          var redirectUrl = responseData.redirect_url;
          if (responseData.updated_references?.length > 0) {
            var param = encodeURIComponent(responseData.updated_references.join(', '));
            var separator = redirectUrl.includes('?') ? '&' : '?';
            redirectUrl += separator + 'refs_updated=' + param;
          }
          window.location = redirectUrl;
        }
      });
    });
  }

  // --- Delete (generic — works for any dialog containing .editor-delete) ---

  if (deleteBtn) {
    deleteBtn.addEventListener('click', async function() {
      var title = deleteBtn.dataset.recipeTitle;
      var referencing = JSON.parse(deleteBtn.dataset.referencingRecipes || '[]');

      var message;
      if (referencing.length > 0) {
        message = 'Delete "' + title + '"?\n\nCross-references in ' + referencing.join(', ') + ' will be converted to plain text.\n\nThis cannot be undone.';
      } else {
        message = 'Delete "' + title + '"?\n\nThis cannot be undone.';
      }

      if (!confirm(message)) return;

      deleteBtn.disabled = true;
      deleteBtn.textContent = 'Deleting\u2026';

      try {
        var response = await fetch(actionUrl, {
          method: 'DELETE',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': EditorUtils.getCsrfToken()
          }
        });

        if (response.ok) {
          var data = await response.json();
          guard.markSaving();
          window.location = data.redirect_url;
        } else {
          EditorUtils.showErrors(errorsDiv, ['Failed to delete (' + response.status + '). Please try again.']);
          deleteBtn.disabled = false;
          deleteBtn.textContent = 'Delete';
        }
      } catch (err) {
        EditorUtils.showErrors(errorsDiv, ['Network error. Please check your connection and try again.']);
        deleteBtn.disabled = false;
        deleteBtn.textContent = 'Delete';
      }
    });
  }
}
