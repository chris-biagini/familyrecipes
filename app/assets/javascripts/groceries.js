(function() {
  'use strict';

  // -----------------------------------------------------------------------
  // GrocerySync — server-driven state with ActionCable sync
  // -----------------------------------------------------------------------

  var GrocerySync = {
    version: 0,
    state: {},
    pending: [],
    storageKey: null,
    urls: {},
    subscription: null,
    heartbeatId: null,
    consumer: null,

    init: function(app) {
      var slug = app.dataset.kitchenSlug;
      this.storageKey = 'grocery-state-' + slug;
      this.pendingKey = 'grocery-pending-' + slug;

      this.urls = {
        state: app.dataset.stateUrl,
        select: app.dataset.selectUrl,
        check: app.dataset.checkUrl,
        customItems: app.dataset.customItemsUrl,
        clear: app.dataset.clearUrl
      };

      this.loadCache();
      this.loadPending();

      if (this.state && Object.keys(this.state).length > 0) {
        GroceryUI.applyState(this.state);
      }

      this.fetchState();
      this.subscribe(slug);
      this.startHeartbeat();
      this.flushPending();
    },

    fetchState: function() {
      var self = this;
      fetch(this.urls.state, {
        headers: { 'Accept': 'application/json' }
      })
      .then(function(response) {
        if (!response.ok) throw new Error('fetch failed');
        return response.json();
      })
      .then(function(data) {
        if (data.version > self.version) {
          var isRemoteUpdate = self.version > 0;
          self.version = data.version;
          self.state = data;
          self.saveCache();
          GroceryUI.applyState(data);
          if (isRemoteUpdate) {
            Notify.show('List updated from another device.');
          }
        }
      })
      .catch(function() {
        // Offline or error — cached state already applied
      });
    },

    sendAction: function(url, params) {
      var self = this;
      var csrfToken = document.querySelector('meta[name="csrf-token"]');
      var method = url === this.urls.clear ? 'DELETE' : 'PATCH';

      return fetch(url, {
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': csrfToken ? csrfToken.content : ''
        },
        body: JSON.stringify(params)
      })
      .then(function(response) {
        if (!response.ok) throw new Error('action failed');
        return response.json();
      })
      .then(function(data) {
        if (data.version) {
          self.version = data.version;
        }
        // Fetch full state to get updated shopping list
        self.fetchState();
      })
      .catch(function() {
        // Queue for retry
        self.pending.push({ url: url, params: params });
        self.savePending();
      });
    },

    flushPending: function() {
      if (this.pending.length === 0) return;

      var queue = this.pending.slice();
      this.pending = [];
      this.savePending();

      var self = this;
      queue.forEach(function(entry) {
        self.sendAction(entry.url, entry.params);
      });
    },

    subscribe: function(slug) {
      if (typeof ActionCable === 'undefined') return;

      var self = this;
      this.consumer = ActionCable.createConsumer();
      this.subscription = this.consumer.subscriptions.create(
        { channel: 'GroceryListChannel', kitchen_slug: slug },
        {
          received: function(data) {
            if (data.version && data.version > self.version) {
              self.fetchState();
            }
          },
          connected: function() {
            self.flushPending();
          }
        }
      );
    },

    startHeartbeat: function() {
      var self = this;
      this.heartbeatId = setInterval(function() {
        self.fetchState();
      }, 30000);
    },

    saveCache: function() {
      try {
        localStorage.setItem(this.storageKey, JSON.stringify({
          version: this.version,
          state: this.state
        }));
      } catch(error) {
        // localStorage full or unavailable
      }
    },

    loadCache: function() {
      try {
        var raw = localStorage.getItem(this.storageKey);
        if (!raw) return;
        var cached = JSON.parse(raw);
        if (cached && cached.version) {
          this.version = cached.version;
          this.state = cached.state || {};
        }
      } catch(error) {
        // Corrupted cache
      }
    },

    savePending: function() {
      try {
        if (this.pending.length > 0) {
          localStorage.setItem(this.pendingKey, JSON.stringify(this.pending));
        } else {
          localStorage.removeItem(this.pendingKey);
        }
      } catch(error) {
        // localStorage full or unavailable
      }
    },

    loadPending: function() {
      try {
        var raw = localStorage.getItem(this.pendingKey);
        if (raw) {
          this.pending = JSON.parse(raw) || [];
        }
      } catch(error) {
        this.pending = [];
      }
    }
  };

  // -----------------------------------------------------------------------
  // GroceryUI — renders state to the DOM and handles user interactions
  // -----------------------------------------------------------------------

  var GroceryUI = {
    app: null,
    aisleCollapseKey: null,

    init: function(app) {
      this.app = app;
      this.aisleCollapseKey = 'grocery-aisles-' + app.dataset.kitchenSlug;
      this.bindRecipeCheckboxes();
      this.bindCustomItemInput();
      this.bindShoppingListEvents();
    },

    applyState: function(state) {
      this.syncCheckboxes(state);
      this.renderShoppingList(state.shopping_list || {});
      this.renderCustomItems(state.custom_items || []);
      this.syncCheckedOff(state.checked_off || []);
      this.renderItemCount();
    },

    // --- Checkbox synchronization ---

    syncCheckboxes: function(state) {
      var selectedRecipes = state.selected_recipes || [];
      var selectedQuickBites = state.selected_quick_bites || [];

      this.app.querySelectorAll('#recipe-selector input[type="checkbox"]').forEach(function(cb) {
        var slug = cb.dataset.slug;
        var typeEl = cb.closest('[data-type]');
        if (!typeEl || !slug) return;

        if (typeEl.dataset.type === 'quick_bite') {
          cb.checked = selectedQuickBites.indexOf(slug) !== -1;
        } else {
          cb.checked = selectedRecipes.indexOf(slug) !== -1;
        }
      });
    },

    // --- Shopping list rendering (DOM construction) ---

    renderShoppingList: function(shoppingList) {
      var container = document.getElementById('shopping-list');
      var aisles = Object.keys(shoppingList);
      var collapsed = this.loadAisleCollapse();

      container.textContent = '';

      if (aisles.length === 0) {
        var emptyMsg = document.createElement('p');
        emptyMsg.id = 'grocery-preview-empty';
        emptyMsg.textContent = 'Your shopping list will appear here.';
        container.appendChild(emptyMsg);
        return;
      }

      var countEl = document.createElement('p');
      countEl.id = 'item-count';
      container.appendChild(countEl);

      var self = this;

      for (var i = 0; i < aisles.length; i++) {
        var aisle = aisles[i];
        var items = shoppingList[aisle];
        var isCollapsed = collapsed.indexOf(aisle) !== -1;

        var details = document.createElement('details');
        details.className = 'aisle';
        details.dataset.aisle = aisle;
        if (!isCollapsed) details.open = true;

        var summary = document.createElement('summary');
        var h3 = document.createElement('h3');
        h3.textContent = aisle;
        var aisleCount = document.createElement('span');
        aisleCount.className = 'aisle-count';
        summary.appendChild(h3);
        summary.appendChild(aisleCount);
        details.appendChild(summary);

        var ul = document.createElement('ul');

        for (var j = 0; j < items.length; j++) {
          var item = items[j];
          var amountStr = formatAmounts(item.amounts);

          var li = document.createElement('li');
          li.dataset.item = item.name;

          var label = document.createElement('label');
          label.className = 'check-off';

          var checkbox = document.createElement('input');
          checkbox.type = 'checkbox';
          checkbox.dataset.item = item.name;

          var nameSpan = document.createElement('span');
          nameSpan.className = 'item-name';
          nameSpan.textContent = item.name;

          label.appendChild(checkbox);
          label.appendChild(nameSpan);

          if (amountStr) {
            var amountSpan = document.createElement('span');
            amountSpan.className = 'item-amount';
            amountSpan.textContent = amountStr;
            label.appendChild(amountSpan);
          }

          li.appendChild(label);
          ul.appendChild(li);
        }

        details.appendChild(ul);
        container.appendChild(details);

        // Bind aisle toggle persistence
        details.addEventListener('toggle', function() {
          self.saveAisleCollapse();
        });
      }
    },

    // --- Custom items ---

    renderCustomItems: function(items) {
      var container = document.getElementById('custom-items-list');
      container.textContent = '';

      for (var i = 0; i < items.length; i++) {
        var name = items[i];
        var li = document.createElement('li');

        var span = document.createElement('span');
        span.textContent = name;

        var btn = document.createElement('button');
        btn.className = 'custom-item-remove';
        btn.type = 'button';
        btn.textContent = '\u00d7';
        btn.setAttribute('aria-label', 'Remove ' + name);
        btn.dataset.item = name;

        li.appendChild(span);
        li.appendChild(btn);
        container.appendChild(li);
      }
    },

    // --- Checked-off state ---

    syncCheckedOff: function(checkedOff) {
      document.querySelectorAll('#shopping-list input[type="checkbox"][data-item]').forEach(function(cb) {
        var name = cb.dataset.item;
        cb.checked = checkedOff.indexOf(name) !== -1;
      });
    },

    // --- Item counts ---

    renderItemCount: function() {
      this.updateAisleCounts();

      var countEl = document.getElementById('item-count');
      if (!countEl) return;

      var total = 0;
      var checked = 0;

      document.querySelectorAll('#shopping-list li[data-item]').forEach(function(li) {
        total++;
        var cb = li.querySelector('input[type="checkbox"]');
        if (cb && cb.checked) checked++;
      });

      var remaining = total - checked;

      if (total === 0) {
        countEl.textContent = '';
      } else if (remaining === 0) {
        countEl.textContent = '\u2713 All done!';
        countEl.classList.add('all-done');
      } else {
        countEl.classList.remove('all-done');
        if (checked > 0) {
          countEl.textContent = remaining + ' of ' + total + ' items remaining';
        } else {
          countEl.textContent = total + (total === 1 ? ' item' : ' items');
        }
      }
    },

    updateAisleCounts: function() {
      document.querySelectorAll('#shopping-list details.aisle').forEach(function(details) {
        var total = 0;
        var checked = 0;

        details.querySelectorAll('li[data-item]').forEach(function(li) {
          total++;
          var cb = li.querySelector('input[type="checkbox"]');
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
    },

    // --- Aisle collapse persistence (personal, localStorage) ---

    saveAisleCollapse: function() {
      var collapsed = [];
      document.querySelectorAll('#shopping-list details.aisle').forEach(function(details) {
        if (!details.open) {
          collapsed.push(details.dataset.aisle);
        }
      });

      try {
        localStorage.setItem(this.aisleCollapseKey, JSON.stringify(collapsed));
      } catch(error) {
        // localStorage full or unavailable
      }
    },

    loadAisleCollapse: function() {
      try {
        var raw = localStorage.getItem(this.aisleCollapseKey);
        return raw ? JSON.parse(raw) : [];
      } catch(error) {
        return [];
      }
    },

    // --- Aisle animation ---

    animateCollapse: function(details) {
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
    },

    animateExpand: function(details) {
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
    },

    // --- Event binding ---

    bindRecipeCheckboxes: function() {
      this.app.querySelectorAll('#recipe-selector input[type="checkbox"]').forEach(function(cb) {
        cb.addEventListener('change', function() {
          var slug = cb.dataset.slug;
          var typeEl = cb.closest('[data-type]');
          var type = typeEl ? typeEl.dataset.type : 'recipe';

          GrocerySync.sendAction(GrocerySync.urls.select, {
            type: type,
            slug: slug,
            selected: cb.checked
          });
        });
      });
    },

    bindCustomItemInput: function() {
      var input = document.getElementById('custom-input');
      var addBtn = document.getElementById('custom-add');

      function addItem() {
        var text = input.value.trim();
        if (!text) return;

        GrocerySync.sendAction(GrocerySync.urls.customItems, {
          item: text,
          action_type: 'add'
        });

        input.value = '';
        input.focus();
      }

      addBtn.addEventListener('click', addItem);
      input.addEventListener('keydown', function(e) {
        if (e.key === 'Enter') {
          e.preventDefault();
          addItem();
        }
      });

      // Delegated remove handler for custom item chips
      document.getElementById('custom-items-list').addEventListener('click', function(e) {
        var btn = e.target.closest('.custom-item-remove');
        if (!btn) return;

        GrocerySync.sendAction(GrocerySync.urls.customItems, {
          item: btn.dataset.item,
          action_type: 'remove'
        });
      });
    },

    bindShoppingListEvents: function() {
      var self = this;

      // Delegated handler for shopping list check-offs
      document.getElementById('shopping-list').addEventListener('change', function(e) {
        var cb = e.target;
        if (!cb.matches('.grocery-item input[type="checkbox"]')) return;

        var name = cb.dataset.item;
        if (!name) return;

        GrocerySync.sendAction(GrocerySync.urls.check, {
          item: name,
          checked: cb.checked
        });

        self.renderItemCount();

        // Auto-collapse aisle when all items checked
        var details = cb.closest('details.aisle');
        if (!details) return;

        if (cb.checked) {
          var allChecked = true;
          details.querySelectorAll('li[data-item]').forEach(function(li) {
            var itemCb = li.querySelector('input[type="checkbox"]');
            if (itemCb && !itemCb.checked) allChecked = false;
          });
          if (allChecked && details.open) {
            self.animateCollapse(details);
          }
        } else {
          if (!details.open) {
            self.animateExpand(details);
          }
        }
      });
    }
  };

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  function formatAmounts(amounts) {
    if (!amounts || amounts.length === 0) return '';

    var parts = [];
    for (var i = 0; i < amounts.length; i++) {
      var value = formatNumber(amounts[i][0]);
      var unit = amounts[i][1];
      parts.push(unit ? value + '\u00a0' + unit : value);
    }
    return parts.join(' + ');
  }

  function formatNumber(val) {
    return parseFloat(val.toFixed(2)).toString();
  }

  function cleanupAnimation(details) {
    var ul = details.querySelector('ul');
    if (!ul) return;
    details.classList.remove('aisle-collapsing', 'aisle-expanding');
    ul.style.height = '';
    ul.style.overflow = '';
    ul.style.opacity = '';
    ul.style.paddingBottom = '';
  }

  // -----------------------------------------------------------------------
  // Init on DOMContentLoaded
  // -----------------------------------------------------------------------

  document.addEventListener('DOMContentLoaded', function() {
    var app = document.getElementById('groceries-app');
    if (!app) return;

    // Reveal JS-only content
    app.classList.remove('hidden-until-js');

    GroceryUI.init(app);
    GrocerySync.init(app);
  });
})();
