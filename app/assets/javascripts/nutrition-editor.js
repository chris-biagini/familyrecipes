// Nutrition editor — extends editor-framework via lifecycle events.
// Handles: dynamic open triggers (per-ingredient buttons), aisle selector, reset buttons.
document.addEventListener('DOMContentLoaded', function() {
  var dialog = document.getElementById('nutrition-editor');
  if (!dialog) return;

  var textarea = document.getElementById('nutrition-editor-textarea');
  var titleEl = dialog.querySelector('.editor-header h2');
  var errorsDiv = dialog.querySelector('.editor-errors');
  var aisleSelect = document.getElementById('nutrition-editor-aisle');
  var aisleInput = document.getElementById('nutrition-editor-aisle-input');

  var currentIngredient = null;
  var originalContent = '';
  var originalAisle = '';

  function currentAisle() {
    return aisleSelect.value === '__other__' ? aisleInput.value.trim() : aisleSelect.value;
  }

  function nutritionUrl(name) {
    var slug = name.replace(/ /g, '-');
    var parts = window.location.pathname.split('/');
    var kitchensIdx = parts.indexOf('kitchens');
    var base = parts.slice(0, kitchensIdx + 2).join('/');
    return base + '/nutrition/' + encodeURIComponent(slug);
  }

  // --- Open triggers (per-ingredient edit buttons) ---

  document.querySelectorAll('.nutrition-edit-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
      currentIngredient = btn.dataset.ingredient;
      textarea.value = btn.dataset.nutritionText;
      originalContent = textarea.value;
      originalAisle = btn.dataset.aisle || '';
      aisleSelect.value = originalAisle;
      if (aisleSelect.value !== originalAisle) aisleSelect.value = '';
      aisleInput.hidden = true;
      aisleInput.value = '';
      titleEl.textContent = currentIngredient;
      EditorUtils.clearErrors(errorsDiv);
      dialog.showModal();
    });
  });

  // --- Aisle select behavior ---

  aisleSelect.addEventListener('change', function() {
    if (aisleSelect.value === '__other__') {
      aisleInput.hidden = false;
      aisleInput.value = '';
      aisleInput.focus();
    } else {
      aisleInput.hidden = true;
      aisleInput.value = '';
    }
  });

  aisleInput.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      aisleInput.hidden = true;
      aisleInput.value = '';
      aisleSelect.value = originalAisle || '';
    }
  });

  // --- Reset buttons (delete kitchen override) ---

  document.querySelectorAll('.nutrition-reset-btn').forEach(function(btn) {
    btn.addEventListener('click', async function() {
      var name = btn.dataset.ingredient;
      if (!confirm('Reset "' + name + '" to built-in nutrition data?')) return;

      btn.disabled = true;
      try {
        var response = await fetch(nutritionUrl(name), {
          method: 'DELETE',
          headers: { 'X-CSRF-Token': EditorUtils.getCsrfToken() }
        });

        if (response.ok) {
          window.location.reload();
        } else {
          btn.disabled = false;
          alert('Failed to reset. Please try again.');
        }
      } catch (err) {
        btn.disabled = false;
        alert('Network error. Please try again.');
      }
    });
  });

  // --- Lifecycle events (claimed by this editor) ---

  dialog.addEventListener('editor:collect', function(e) {
    e.detail.handled = true;
    var nutritionChanged = textarea.value !== originalContent;
    e.detail.data = {
      label_text: nutritionChanged ? textarea.value : '',
      aisle: currentAisle()
    };
  });

  dialog.addEventListener('editor:save', function(e) {
    e.detail.handled = true;
    e.detail.saveFn = function() {
      return EditorUtils.saveRequest(nutritionUrl(currentIngredient), 'POST', e.detail.data);
    };
  });

  dialog.addEventListener('editor:modified', function(e) {
    e.detail.handled = true;
    e.detail.modified = textarea.value !== originalContent || currentAisle() !== originalAisle;
  });

  dialog.addEventListener('editor:reset', function(e) {
    e.detail.handled = true;
    textarea.value = originalContent;
    aisleSelect.value = originalAisle || '';
    aisleInput.hidden = true;
    aisleInput.value = '';
  });
});
