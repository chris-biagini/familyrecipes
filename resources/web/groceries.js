(function() {
  var STORAGE_KEY = 'groceries-state';
  var initComplete = false;

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

  // --- Aisle index mapping (for localStorage collapse persistence) ---

  var aisleElements = [];  // index -> details element

  function buildAisleIndex() {
    document.querySelectorAll('#grocery-list details.aisle').forEach(function(details) {
      aisleElements.push(details);
    });
  }

  // --- Compact encoding ---

  function encodeIndices(indices) {
    var sorted = indices.slice().sort(function(a, b) { return a - b; });
    var str = '';
    for (var i = 0; i < sorted.length; i++) {
      str += String.fromCharCode(97 + Math.floor(sorted[i] / 26))
           + String.fromCharCode(97 + sorted[i] % 26);
    }
    return str;
  }

  function decodeIndices(str) {
    var indices = [];
    for (var i = 0; i + 1 < str.length; i += 2) {
      indices.push((str.charCodeAt(i) - 97) * 26 + str.charCodeAt(i + 1) - 97);
    }
    return indices;
  }

  function encodeCustomItem(text) {
    return encodeURIComponent(text)
      .replace(/-/g, '%2D')
      .replace(/\./g, '%2E')
      .replace(/%20/g, '-');
  }

  function decodeCustomItem(str) {
    return decodeURIComponent(str.replace(/-/g, '%20'));
  }

  function getRawParam(name) {
    var match = window.location.search.match(new RegExp('[?&]' + name + '=([^&]*)'));
    return match ? match[1] : null;
  }

  // --- Unified state encode/decode ---

  function encodeState() {
    var encoded = {};

    var ids = Array.from(state.selectedIds);
    if (ids.length > 0) {
      var indices = [];
      ids.forEach(function(id) {
        if (recipeIndexMap[id] !== undefined) indices.push(recipeIndexMap[id]);
      });
      if (indices.length > 0) encoded.s = encodeIndices(indices);
    }

    if (state.customItems.length > 0) {
      encoded.c = state.customItems.map(encodeCustomItem).join('.');
    }

    if (state.checkedOff.size > 0) {
      encoded.x = Array.from(state.checkedOff).map(encodeCustomItem).join('.');
    }

    return encoded;
  }

  function decodeState(obj) {
    var result = { selectedIds: [], customItems: [], checkedOff: [] };

    if (obj.s) {
      decodeIndices(obj.s).forEach(function(i) {
        if (i >= 0 && i < recipeIdList.length) {
          result.selectedIds.push(recipeIdList[i]);
        }
      });
    }

    if (obj.c) {
      obj.c.split('.').forEach(function(encoded) {
        if (encoded) result.customItems.push(decodeCustomItem(encoded));
      });
    }

    if (obj.x) {
      obj.x.split('.').forEach(function(encoded) {
        if (encoded) result.checkedOff.push(decodeCustomItem(encoded));
      });
    }

    return result;
  }

  function applyState(decoded) {
    state.selectedIds = new Set(decoded.selectedIds);
    state.customItems = decoded.customItems.slice();
    state.checkedOff = new Set(decoded.checkedOff);
  }

  function snapshotState() {
    return {
      selectedIds: Array.from(state.selectedIds),
      customItems: state.customItems.slice(),
      checkedOff: Array.from(state.checkedOff)
    };
  }

  // --- Aisle state ---

  function encodeAisleState() {
    var collapsed = [];
    for (var i = 0; i < aisleElements.length; i++) {
      if (!aisleElements[i].hidden && !aisleElements[i].open) {
        collapsed.push(i);
      }
    }
    return collapsed.length > 0 ? encodeIndices(collapsed) : undefined;
  }

  function restoreAisleState(encoded) {
    if (!encoded) return;
    var indices = decodeIndices(encoded);
    indices.forEach(function(i) {
      if (i >= 0 && i < aisleElements.length && !aisleElements[i].hidden) {
        aisleElements[i].open = false;
      }
    });
  }

  // --- State persistence ---

  function saveState() {
    var encoded = encodeState();
    var aisles = encodeAisleState();
    if (aisles) encoded.a = aisles;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(encoded));
  }

  function loadFromStorage() {
    var raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    try {
      var obj = JSON.parse(raw);
      if (!obj.s && !obj.c && !obj.x && !obj.a) return null;
      return { decoded: decodeState(obj), aisles: obj.a || null };
    } catch(e) {
      return null;
    }
  }

  function parseStateFromUrl() {
    var s = getRawParam('s');
    var c = getRawParam('c');
    var x = getRawParam('x');
    if (!s && !c && !x) return null;

    return decodeState({ s: s, c: c, x: x });
  }

  function cleanUrl() {
    history.replaceState(null, '', window.location.pathname);
  }

  function statesMatch(a, b) {
    var aIds = a.selectedIds.slice().sort();
    var bIds = b.selectedIds.slice().sort();
    if (JSON.stringify(aIds) !== JSON.stringify(bIds)) return false;

    var aItems = a.customItems.slice().sort();
    var bItems = b.customItems.slice().sort();
    if (JSON.stringify(aItems) !== JSON.stringify(bItems)) return false;

    var aChecked = a.checkedOff.slice().sort();
    var bChecked = b.checkedOff.slice().sort();
    return JSON.stringify(aChecked) === JSON.stringify(bChecked);
  }

  function applyStateToCheckboxes() {
    document.querySelectorAll('input[type="checkbox"][data-ingredients]').forEach(function(cb) {
      var id = cb.id.replace(/-checkbox$/, '');
      cb.checked = state.selectedIds.has(id);
    });
  }

  // --- Grocery list logic ---

  function formatQtyNumber(val) {
    return parseFloat(val.toFixed(2)).toString();
  }

  function aggregateQuantities(info) {
    var recipes = info.recipes; // Map of title -> amounts array
    if (recipes.size === 0) return { display: null, tooltip: null };

    // Collect all amounts across all recipes
    var sums = {};       // unit (or "") -> total
    var hasNull = false;  // any unquantified occurrence
    var perRecipe = [];   // for tooltip

    recipes.forEach(function(amounts, title) {
      var recipeParts = [];
      amounts.forEach(function(a) {
        if (a === null) {
          hasNull = true;
        } else {
          var val = a[0];
          var unit = a[1] || '';
          sums[unit] = (sums[unit] || 0) + val;
          var part = formatQtyNumber(val);
          if (unit) part += '\u00a0' + unit;
          recipeParts.push(part);
        }
      });
      if (recipeParts.length > 0) {
        perRecipe.push(recipeParts.join(' + ') + ' from ' + title);
      }
    });

    // Build display string
    var parts = [];
    var units = Object.keys(sums);
    for (var i = 0; i < units.length; i++) {
      var unit = units[i];
      var str = formatQtyNumber(sums[unit]);
      if (unit) str += '\u00a0' + unit;
      parts.push(str);
    }

    var display = null;
    if (parts.length > 0) {
      display = ' (' + parts.join(' + ') + (hasNull ? '+' : '') + ')';
    }

    // Build tooltip
    var tooltip = null;
    if (perRecipe.length > 1) {
      tooltip = perRecipe.join(', ');
    } else if (perRecipe.length === 0 && recipes.size > 0) {
      tooltip = 'Needed for: ' + Array.from(recipes.keys()).join(', ');
    }

    return { display: display, tooltip: tooltip };
  }

  function updateGroceryList() {
    // Build map of needed ingredients: name -> { recipes: Map<title, amounts> }
    var neededMap = new Map();

    // From checked recipe checkboxes
    document.querySelectorAll('input[type="checkbox"][data-ingredients]').forEach(function(cb) {
      if (!cb.checked) return;
      var recipeTitle = cb.dataset.title;
      var items = JSON.parse(cb.dataset.ingredients);
      items.forEach(function(entry) {
        var name = entry[0];
        var amounts = entry[1];
        if (!neededMap.has(name)) neededMap.set(name, { recipes: new Map() });
        neededMap.get(name).recipes.set(recipeTitle, amounts);
      });
    });

    // From custom items
    state.customItems.forEach(function(name) {
      if (!neededMap.has(name)) neededMap.set(name, { recipes: new Map() });
    });

    // Show/hide static list items and match against neededMap
    document.querySelectorAll('#grocery-list .aisle:not(#misc-aisle) li[data-item]').forEach(function(li) {
      var name = li.getAttribute('data-item');
      if (neededMap.has(name)) {
        li.hidden = false;
        var info = neededMap.get(name);
        var qty = aggregateQuantities(info);
        var qtySpan = li.querySelector('.qty');
        if (qtySpan) qtySpan.textContent = qty.display || '';
        if (qty.tooltip) {
          li.setAttribute('title', qty.tooltip);
        } else if (info.recipes.size > 0) {
          li.setAttribute('title', 'Needed for: ' + Array.from(info.recipes.keys()).join(', '));
        } else {
          li.removeAttribute('title');
        }
        neededMap.delete(name);
      } else {
        li.hidden = true;
        li.removeAttribute('title');
        var qtySpan = li.querySelector('.qty');
        if (qtySpan) qtySpan.textContent = '';
        // Uncheck when hidden
        var cb = li.querySelector('input[type="checkbox"]');
        if (cb) cb.checked = false;
      }
    });

    // Leftovers go to Miscellaneous
    var misc = document.getElementById('misc-items');
    misc.innerHTML = '';
    neededMap.forEach(function(info, name) {
      var li = document.createElement('li');
      li.setAttribute('data-item', name);
      var label = document.createElement('label');
      label.className = 'check-off';
      var checkbox = document.createElement('input');
      checkbox.type = 'checkbox';
      var span = document.createElement('span');
      var qty = aggregateQuantities(info);
      span.textContent = name;
      var qtySpan = document.createElement('span');
      qtySpan.className = 'qty';
      qtySpan.textContent = qty.display || '';
      span.appendChild(qtySpan);
      label.appendChild(checkbox);
      label.appendChild(span);
      li.appendChild(label);
      if (qty.tooltip) {
        li.setAttribute('title', qty.tooltip);
      } else if (info.recipes.size > 0) {
        li.setAttribute('title', 'Needed for: ' + Array.from(info.recipes.keys()).join(', '));
      }
      misc.appendChild(li);
    });

    // Hide empty aisles, only force-open newly visible ones
    document.querySelectorAll('#grocery-list details.aisle').forEach(function(details) {
      var visibleItems = details.querySelectorAll('li:not([hidden])');
      var count = visibleItems.length;

      if (count === 0) {
        details.hidden = true;
      } else {
        var wasHidden = details.hidden;
        details.hidden = false;
        if (wasHidden) details.open = true;
      }
    });

    // Restore check-off states
    restoreCheckOffs();

    // Update item count display
    updateItemCount();
  }

  // --- Item count ---

  function getItemCountInfo() {
    var total = 0;
    var checked = 0;
    document.querySelectorAll('#grocery-list li:not([hidden])').forEach(function(li) {
      total++;
      var cb = li.querySelector('.check-off input[type="checkbox"]');
      if (cb && cb.checked) checked++;
    });
    return { total: total, checked: checked, remaining: total - checked };
  }

  function updateAisleCounts() {
    document.querySelectorAll('#grocery-list details.aisle:not([hidden])').forEach(function(details) {
      var total = 0;
      var checked = 0;
      details.querySelectorAll('li:not([hidden])').forEach(function(li) {
        total++;
        var cb = li.querySelector('.check-off input[type="checkbox"]');
        if (cb && cb.checked) checked++;
      });
      var countSpan = details.querySelector('.aisle-count');
      if (!countSpan) return;
      var remaining = total - checked;
      if (remaining === 0 && total > 0) {
        countSpan.textContent = '\u2713';
        countSpan.classList.add('aisle-done');
      } else {
        countSpan.textContent = '(' + remaining + ')';
        countSpan.classList.remove('aisle-done');
      }
    });
  }

  function updateItemCount() {
    updateAisleCounts();
    var info = getItemCountInfo();
    var countEl = document.getElementById('item-count');
    var emptyEl = document.getElementById('grocery-preview-empty');
    var groceryList = document.getElementById('grocery-list');

    if (info.total > 0) {
      emptyEl.style.display = 'none';
      groceryList.style.display = '';

      if (info.remaining === 0) {
        countEl.textContent = '\u2713 All done!';
        countEl.classList.add('all-done');
      } else {
        countEl.classList.remove('all-done');
        if (info.checked > 0) {
          countEl.textContent = info.remaining + ' of ' + info.total + ' items needed';
        } else {
          countEl.textContent = info.total + (info.total === 1 ? ' item' : ' items');
        }
      }
    } else {
      countEl.textContent = '';
      countEl.classList.remove('all-done');
      emptyEl.style.display = '';
      groceryList.style.display = 'none';
    }
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
    updateItemCount();
    updateShareSection();

    // Auto-collapse/expand aisle
    var details = li.closest('details.aisle');
    if (details) {
      if (cb.checked) {
        var allChecked = true;
        details.querySelectorAll('li:not([hidden])').forEach(function(item) {
          var itemCb = item.querySelector('.check-off input[type="checkbox"]');
          if (itemCb && !itemCb.checked) allChecked = false;
        });
        if (allChecked && details.open) {
          animateCollapse(details);
        }
      } else {
        if (!details.open) {
          animateExpand(details);
        }
      }
    }
  }

  // --- Aisle animation ---

  function cleanupAnimation(details) {
    var ul = details.querySelector('ul');
    if (!ul) return;
    details.classList.remove('aisle-collapsing', 'aisle-expanding');
    ul.style.height = '';
    ul.style.overflow = '';
    ul.style.opacity = '';
    ul.style.paddingBottom = '';
  }

  function animateCollapse(details) {
    var ul = details.querySelector('ul');
    if (!ul) { details.open = false; return; }

    cleanupAnimation(details);

    var startHeight = ul.scrollHeight;
    ul.style.height = startHeight + 'px';
    ul.style.overflow = 'hidden';
    ul.offsetHeight; // force reflow

    details.classList.add('aisle-collapsing');
    ul.style.height = '0';
    ul.style.opacity = '0';
    ul.style.paddingBottom = '0';

    function onEnd(e) {
      if (e.target !== ul) return;
      ul.removeEventListener('transitionend', onEnd);
      details.classList.remove('aisle-collapsing');
      ul.style.height = '';
      ul.style.overflow = '';
      ul.style.opacity = '';
      ul.style.paddingBottom = '';
      details.open = false;
    }
    ul.addEventListener('transitionend', onEnd);

    // Fallback in case transitionend doesn't fire
    setTimeout(function() {
      if (details.classList.contains('aisle-collapsing')) {
        details.classList.remove('aisle-collapsing');
        ul.style.height = '';
        ul.style.overflow = '';
        ul.style.opacity = '';
        ul.style.paddingBottom = '';
        details.open = false;
      }
    }, 400);
  }

  function animateExpand(details) {
    var ul = details.querySelector('ul');
    if (!ul) { details.open = true; return; }

    cleanupAnimation(details);

    details.open = true;
    var targetHeight = ul.scrollHeight;
    ul.style.height = '0';
    ul.style.opacity = '0';
    ul.style.overflow = 'hidden';
    ul.style.paddingBottom = '0';
    ul.offsetHeight; // force reflow

    details.classList.add('aisle-expanding');
    ul.style.height = targetHeight + 'px';
    ul.style.opacity = '1';
    ul.style.paddingBottom = '';

    function onEnd(e) {
      if (e.target !== ul) return;
      ul.removeEventListener('transitionend', onEnd);
      details.classList.remove('aisle-expanding');
      ul.style.height = '';
      ul.style.overflow = '';
      ul.style.opacity = '';
    }
    ul.addEventListener('transitionend', onEnd);

    setTimeout(function() {
      if (details.classList.contains('aisle-expanding')) {
        details.classList.remove('aisle-expanding');
        ul.style.height = '';
        ul.style.overflow = '';
        ul.style.opacity = '';
      }
    }, 400);
  }

  // --- Custom items ---

  function addCustomItem(name) {
    name = name.trim();
    if (!name) return;
    var lowerName = name.toLowerCase();
    if (state.customItems.some(function(item) { return item.toLowerCase() === lowerName; })) return;
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
    var encoded = encodeState();
    var base = window.location.origin + window.location.pathname;
    var params = [];

    if (encoded.s) params.push('s=' + encoded.s);
    if (encoded.c) params.push('c=' + encoded.c);
    if (encoded.x) params.push('x=' + encoded.x);

    return params.length > 0 ? base + '?' + params.join('&') : base;
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
      container.textContent = '';
      var msg = document.createElement('p');
      msg.style.cssText = 'color: var(--muted-text); font-size: 0.85rem; text-align: center;';
      msg.textContent = 'List too large for QR code. Use the link below instead.';
      container.appendChild(msg);
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

  // --- Init ---

  document.addEventListener('DOMContentLoaded', function() {
    // Reveal JS-only elements
    document.querySelectorAll('.hidden-until-js').forEach(function(el) {
      el.classList.remove('hidden-until-js');
    });

    // Build index mappings (must happen before state parsing)
    buildRecipeIndex();
    buildAisleIndex();

    // Mark all aisles hidden so updateGroceryList treats them as "new"
    // and opens them when they first gain items
    aisleElements.forEach(function(d) { d.hidden = true; });

    // Parse state sources
    var urlState = parseStateFromUrl();
    var stored = loadFromStorage();
    var storedAisles = null;

    function finishInit() {
      applyStateToCheckboxes();
      renderChips();
      updateGroceryList();
      updateShareSection();
    }

    if (!urlState) {
      // Branch 1: No URL params — load from localStorage silently
      if (stored) {
        applyState(stored.decoded);
        storedAisles = stored.aisles;
      }
      finishInit();
      if (storedAisles) restoreAisleState(storedAisles);

    } else {
      var storedDecoded = stored ? stored.decoded : null;

      if (storedDecoded && statesMatch(urlState, storedDecoded)) {
        // Branch 2: URL matches stored state — load silently
        applyState(storedDecoded);
        storedAisles = stored.aisles;
        cleanUrl();
        finishInit();
        if (storedAisles) restoreAisleState(storedAisles);

      } else {
        // Branch 3: URL differs (or no stored state) — clobber with undo
        applyState(urlState);
        cleanUrl();
        finishInit();

        var info = getItemCountInfo();
        var message = 'List loaded.';
        if (info.total > 0) {
          if (info.checked > 0) {
            message += ' ' + info.remaining + ' of ' + info.total + ' items needed.';
          } else {
            message += ' ' + info.total + (info.total === 1 ? ' item.' : ' items.');
          }
        }

        Notify.show(message, {
          action: storedDecoded ? { label: 'Undo', callback: function() {
            applyState(storedDecoded);
            applyStateToCheckboxes();
            renderChips();
            saveState();
            updateGroceryList();
            updateShareSection();
          }} : null
        });
      }
    }

    // Init complete — enable aisle toggle persistence
    initComplete = true;
    saveState();

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

    // Aisle toggle persistence
    document.querySelectorAll('#grocery-list details.aisle').forEach(function(details) {
      details.addEventListener('toggle', function() {
        if (initComplete) saveState();
      });
    });

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

  });
})();
