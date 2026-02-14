(function() {
  var STORAGE_KEY = 'groceries-state';

  // Central state
  var state = {
    selectedIds: new Set(),
    customItems: [],
    checkedOff: new Set()
  };

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
    if (!r && !c) return false;

    if (r) {
      r.split(',').forEach(function(id) {
        if (id.trim()) state.selectedIds.add(id.trim());
      });
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

  // --- Custom items chip UI ---

  function addCustomItem(name) {
    name = name.trim();
    if (!name) return;
    if (state.customItems.indexOf(name) !== -1) return;
    state.customItems.push(name);
    renderChips();
    saveState();
    updateGroceryList();
  }

  function removeCustomItem(name) {
    state.customItems = state.customItems.filter(function(item) { return item !== name; });
    renderChips();
    saveState();
    updateGroceryList();
  }

  function renderChips() {
    var container = document.getElementById('custom-chips');
    container.innerHTML = '';
    state.customItems.forEach(function(name) {
      var chip = document.createElement('span');
      chip.className = 'chip';
      chip.textContent = name;
      var btn = document.createElement('button');
      btn.className = 'chip-remove';
      btn.type = 'button';
      btn.textContent = '\u00d7';
      btn.setAttribute('aria-label', 'Remove ' + name);
      btn.addEventListener('click', function() { removeCustomItem(name); });
      chip.appendChild(btn);
      container.appendChild(chip);
    });
  }

  // --- Sharing ---

  function buildShareUrl() {
    var url = new URL(window.location.pathname, window.location.origin);
    var ids = Array.from(state.selectedIds);
    if (ids.length > 0) url.searchParams.set('r', ids.join(','));
    if (state.customItems.length > 0) url.searchParams.set('c', state.customItems.join('|'));
    return url.toString();
  }

  function handleShare() {
    var ids = Array.from(state.selectedIds);
    if (ids.length === 0 && state.customItems.length === 0) return;

    var url = buildShareUrl();

    if (navigator.share) {
      navigator.share({ title: 'Grocery List', url: url }).catch(function() {});
    } else {
      showQrCode(url);
    }
  }

  function showQrCode(url) {
    var container = document.getElementById('qr-container');

    // Toggle off if already showing
    if (container.querySelector('svg')) {
      container.innerHTML = '';
      return;
    }

    try {
      var qr = qrcodegen.QrCode.encodeText(url, qrcodegen.QrCode.Ecc.LOW);
      container.innerHTML = qr.toSvgString(2);
    } catch(e) {
      container.textContent = 'Could not generate QR code.';
    }
  }

  // --- Desktop aisle behavior ---

  function openAislesOnDesktop() {
    if (window.innerWidth >= 700) {
      document.querySelectorAll('#grocery-list details.aisle:not([hidden])').forEach(function(d) {
        d.open = true;
      });
    }
  }

  // --- Service worker ---

  function registerServiceWorker() {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('sw.js').catch(function() {});
    }
  }

  // --- Init ---

  document.addEventListener('DOMContentLoaded', function() {
    // Reveal JS-only elements
    document.querySelectorAll('.hidden-until-js').forEach(function(el) {
      el.classList.remove('hidden-until-js');
    });

    // Load state: URL params take priority, then localStorage
    if (!loadStateFromUrl()) {
      loadStateFromStorage();
    }
    applyStateToCheckboxes();
    renderChips();

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

    // Share button
    document.getElementById('share-button').addEventListener('click', handleShare);

    // Initial grocery list render
    updateGroceryList();
    openAislesOnDesktop();

    // Register service worker
    registerServiceWorker();
  });
})();
