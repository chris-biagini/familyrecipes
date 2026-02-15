(function() {
  var STORAGE_KEY = 'groceries-state';

  // Central state
  var state = {
    selectedIds: new Set(),
    customItems: [],
    checkedOff: new Set()
  };

  // --- Recipe index mapping (for compact URLs) ---

  var recipeIdList = [];   // index -> id
  var recipeIndexMap = {}; // id -> index

  function buildRecipeIndex() {
    document.querySelectorAll('input[type="checkbox"][data-ingredients]').forEach(function(cb) {
      var id = cb.id.replace(/-checkbox$/, '');
      recipeIndexMap[id] = recipeIdList.length;
      recipeIdList.push(id);
    });
  }

  function recipeListHash() {
    var str = recipeIdList.join(',');
    var h = 0;
    for (var i = 0; i < str.length; i++) {
      h = ((h << 5) - h + str.charCodeAt(i)) | 0;
    }
    return (h >>> 0).toString(36).slice(0, 4);
  }

  // --- State persistence ---

  function saveState() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      selectedIds: Array.from(state.selectedIds),
      customItems: state.customItems,
      checkedOff: Array.from(state.checkedOff)
    }));
  }

  function loadStateFromStorage() {
    var raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return false;
    try {
      var data = JSON.parse(raw);
      if (data.selectedIds) data.selectedIds.forEach(function(id) { state.selectedIds.add(id); });
      if (data.customItems) state.customItems = data.customItems;
      if (data.checkedOff) data.checkedOff.forEach(function(id) { state.checkedOff.add(id); });
      return true;
    } catch(e) {
      return false;
    }
  }

  function loadStateFromUrl() {
    var params = new URLSearchParams(window.location.search);
    var r = params.get('r');
    var c = params.get('c');
    var h = params.get('h');
    if (!r && !c) return false;

    if (r && h) {
      if (h === recipeListHash()) {
        r.split('.').forEach(function(idx) {
          var i = parseInt(idx, 10);
          if (i >= 0 && i < recipeIdList.length) {
            state.selectedIds.add(recipeIdList[i]);
          }
        });
      }
      // Stale hash: silently skip recipe selections
    }
    if (c) {
      c.split('|').forEach(function(item) {
        if (item.trim()) state.customItems.push(item.trim());
      });
    }

    // Clean URL without reload
    history.replaceState(null, '', window.location.pathname);
    return true;
  }

  function applyStateToCheckboxes() {
    state.selectedIds.forEach(function(id) {
      var cb = document.getElementById(id + '-checkbox');
      if (cb) cb.checked = true;
    });
  }

  // --- Grocery list logic ---

  function updateGroceryList() {
    // Build map of needed ingredients: name -> Set of recipe titles
    var neededMap = new Map();

    // From checked recipe checkboxes
    document.querySelectorAll('input[type="checkbox"][data-ingredients]').forEach(function(cb) {
      if (!cb.checked) return;
      var recipeTitle = cb.dataset.title;
      var items = JSON.parse(cb.dataset.ingredients);
      items.forEach(function(name) {
        if (!neededMap.has(name)) neededMap.set(name, new Set());
        neededMap.get(name).add(recipeTitle);
      });
    });

    // From custom items
    state.customItems.forEach(function(name) {
      if (!neededMap.has(name)) neededMap.set(name, new Set());
    });

    // Show/hide static list items and match against neededMap
    document.querySelectorAll('#grocery-list .aisle:not(#misc-aisle) li[data-item]').forEach(function(li) {
      var name = li.getAttribute('data-item');
      if (neededMap.has(name)) {
        li.hidden = false;
        var titles = neededMap.get(name);
        if (titles.size > 0) {
          li.setAttribute('title', 'Needed for: ' + Array.from(titles).join(', '));
        } else {
          li.removeAttribute('title');
        }
        neededMap.delete(name);
      } else {
        li.hidden = true;
        li.removeAttribute('title');
        // Uncheck when hidden
        var cb = li.querySelector('input[type="checkbox"]');
        if (cb) cb.checked = false;
      }
    });

    // Leftovers go to Miscellaneous
    var misc = document.getElementById('misc-items');
    misc.innerHTML = '';
    neededMap.forEach(function(titles, name) {
      var li = document.createElement('li');
      li.setAttribute('data-item', name);
      var label = document.createElement('label');
      label.className = 'check-off';
      var checkbox = document.createElement('input');
      checkbox.type = 'checkbox';
      var span = document.createElement('span');
      span.textContent = name;
      label.appendChild(checkbox);
      label.appendChild(span);
      li.appendChild(label);
      if (titles.size > 0) {
        li.setAttribute('title', 'Needed for: ' + Array.from(titles).join(', '));
      }
      misc.appendChild(li);
    });

    // Hide empty aisles, update counts
    var totalItems = 0;
    document.querySelectorAll('#grocery-list details.aisle').forEach(function(details) {
      var visibleItems = details.querySelectorAll('li:not([hidden])');
      var count = visibleItems.length;
      totalItems += count;

      if (count === 0) {
        details.hidden = true;
      } else {
        details.hidden = false;
        var countSpan = details.querySelector('.aisle-count');
        if (countSpan) countSpan.textContent = '(' + count + ')';
      }
    });

    // Update total count and empty state
    var countEl = document.getElementById('item-count');
    var emptyEl = document.getElementById('grocery-preview-empty');
    var groceryList = document.getElementById('grocery-list');

    if (totalItems > 0) {
      countEl.textContent = totalItems + (totalItems === 1 ? ' item' : ' items');
      emptyEl.style.display = 'none';
      groceryList.style.display = '';
    } else {
      countEl.textContent = '';
      emptyEl.style.display = '';
      groceryList.style.display = 'none';
    }

    // Restore check-off states
    restoreCheckOffs();
  }

  // --- Check-off ---

  function restoreCheckOffs() {
    document.querySelectorAll('#grocery-list li:not([hidden])').forEach(function(li) {
      var name = li.getAttribute('data-item');
      var cb = li.querySelector('.check-off input[type="checkbox"]');
      if (cb && name) {
        cb.checked = state.checkedOff.has(name);
      }
    });
  }

  function handleCheckOff(e) {
    var cb = e.target;
    if (!cb.matches('.check-off input[type="checkbox"]')) return;
    var li = cb.closest('li');
    var name = li ? li.getAttribute('data-item') : null;
    if (!name) return;

    if (cb.checked) {
      state.checkedOff.add(name);
    } else {
      state.checkedOff.delete(name);
    }
    saveState();
  }

  // --- Custom items ---

  function addCustomItem(name) {
    name = name.trim();
    if (!name) return;
    if (state.customItems.indexOf(name) !== -1) return;
    state.customItems.push(name);
    renderChips();
    saveState();
    updateGroceryList();
    updateShareSection();
  }

  function removeCustomItem(name) {
    state.customItems = state.customItems.filter(function(item) { return item !== name; });
    renderChips();
    saveState();
    updateGroceryList();
    updateShareSection();
  }

  function renderChips() {
    var container = document.getElementById('custom-items-list');
    container.innerHTML = '';
    state.customItems.forEach(function(name) {
      var li = document.createElement('li');
      var span = document.createElement('span');
      span.textContent = name;
      var btn = document.createElement('button');
      btn.className = 'custom-item-remove';
      btn.type = 'button';
      btn.textContent = '\u00d7';
      btn.setAttribute('aria-label', 'Remove ' + name);
      btn.addEventListener('click', function() { removeCustomItem(name); });
      li.appendChild(span);
      li.appendChild(btn);
      container.appendChild(li);
    });
  }

  // --- Sharing ---

  function buildShareUrl() {
    var url = new URL(window.location.pathname, window.location.origin);
    var ids = Array.from(state.selectedIds);
    if (ids.length > 0) {
      var indices = [];
      ids.forEach(function(id) {
        if (recipeIndexMap[id] !== undefined) indices.push(recipeIndexMap[id]);
      });
      url.searchParams.set('h', recipeListHash());
      url.searchParams.set('r', indices.join('.'));
    }
    if (state.customItems.length > 0) {
      url.searchParams.set('c', state.customItems.join('|'));
    }
    return url.toString();
  }

  function qrToSvg(qr, border) {
    var size = qr.size + border * 2;
    var parts = [];
    for (var y = 0; y < qr.size; y++) {
      for (var x = 0; x < qr.size; x++) {
        if (qr.getModule(x, y))
          parts.push('M' + (x + border) + ',' + (y + border) + 'h1v1h-1z');
      }
    }
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + size + ' ' + size + '">'
      + '<rect width="100%" height="100%" fill="#fff"/>'
      + '<path d="' + parts.join(' ') + '" fill="#000"/></svg>';
  }

  var ICON_SHARE = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
    + '<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/>'
    + '<polyline points="16 6 12 2 8 6"/>'
    + '<line x1="12" y1="2" x2="12" y2="15"/></svg>';

  var ICON_COPY = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
    + '<rect x="9" y="9" width="13" height="13" rx="2"/>'
    + '<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>';

  var canShare = typeof navigator.share === 'function';

  function updateShareSection() {
    var url = buildShareUrl();

    // Update URL display
    document.getElementById('share-url').textContent = url;

    // Update QR code
    var container = document.getElementById('qr-container');
    try {
      var qr = qrcodegen.QrCode.encodeText(url, qrcodegen.QrCode.Ecc.LOW);
      container.innerHTML = qrToSvg(qr, 2);
    } catch(e) {
      container.innerHTML = '';
    }

    // Clear any previous feedback
    document.getElementById('share-feedback').hidden = true;
  }

  function copyToClipboard(text) {
    // Try the modern API first (requires secure context)
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }
    // Fallback for non-secure contexts (e.g. HTTP dev server)
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
    return Promise.resolve();
  }

  function handleShareAction() {
    var url = buildShareUrl();
    var feedback = document.getElementById('share-feedback');

    if (canShare) {
      navigator.share({ title: 'Grocery List', url: url }).catch(function() {});
    } else {
      copyToClipboard(url).then(function() {
        feedback.textContent = 'Copied to clipboard';
        feedback.hidden = false;
        setTimeout(function() { feedback.hidden = true; }, 2000);
      });
    }
  }

  function selectShareUrl() {
    var range = document.createRange();
    range.selectNodeContents(document.getElementById('share-url'));
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  }

  // --- Desktop aisle behavior ---

  function openAislesOnDesktop() {
    if (window.innerWidth >= 700) {
      document.querySelectorAll('#grocery-list details.aisle:not([hidden])').forEach(function(d) {
        d.open = true;
      });
    }
  }

  // --- Init ---

  document.addEventListener('DOMContentLoaded', function() {
    // Reveal JS-only elements
    document.querySelectorAll('.hidden-until-js').forEach(function(el) {
      el.classList.remove('hidden-until-js');
    });

    // Build recipe index mapping (must happen before URL loading)
    buildRecipeIndex();

    // Load state: URL params take priority, then localStorage
    var loadedFromUrl = loadStateFromUrl();
    if (!loadedFromUrl) {
      loadStateFromStorage();
    } else {
      saveState();
    }
    applyStateToCheckboxes();
    renderChips();

    if (loadedFromUrl) {
      var notice = document.getElementById('url-loaded-notice');
      notice.textContent = 'List loaded from shared link';
      notice.hidden = false;
      setTimeout(function() { notice.hidden = true; }, 3000);
    }

    // Sync selectedIds from checkbox state
    function syncSelectedIds() {
      state.selectedIds.clear();
      document.querySelectorAll('input[type="checkbox"][data-ingredients]').forEach(function(cb) {
        if (cb.checked) {
          state.selectedIds.add(cb.id.replace(/-checkbox$/, ''));
        }
      });
    }

    // Recipe checkbox changes
    document.querySelectorAll('input[type="checkbox"][data-ingredients]').forEach(function(cb) {
      cb.addEventListener('change', function() {
        syncSelectedIds();
        saveState();
        updateGroceryList();
        updateShareSection();
      });
    });

    // Check-off changes (delegated)
    document.getElementById('grocery-list').addEventListener('change', handleCheckOff);

    // Custom item input
    var customInput = document.getElementById('custom-input');
    var customAdd = document.getElementById('custom-add');
    customAdd.addEventListener('click', function() {
      addCustomItem(customInput.value);
      customInput.value = '';
      customInput.focus();
    });
    customInput.addEventListener('keydown', function(e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        addCustomItem(customInput.value);
        customInput.value = '';
      }
    });

    // Share/copy button — set icon based on platform capability
    var shareBtn = document.getElementById('share-action');
    shareBtn.innerHTML = canShare ? ICON_SHARE : ICON_COPY;
    shareBtn.addEventListener('click', handleShareAction);

    // Click URL to select all
    document.getElementById('share-url').addEventListener('click', selectShareUrl);

    // Initial render
    updateGroceryList();
    updateShareSection();
    openAislesOnDesktop();

  });
})();
