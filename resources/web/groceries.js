    (function(){
      const STORAGE_KEY = 'groceries-state';
      const FREEFORM_KEY = 'groceries-freeform';

      function saveState() {
        const ids = Array.from(
          document.querySelectorAll('input[type="checkbox"][data-ingredients]:checked')
        ).map(cb => cb.id.replace(/-checkbox$/, ''));
        localStorage.setItem(STORAGE_KEY, JSON.stringify(ids));
      }

      function saveFreeform() {
        const freeform = document.getElementById('freeform-entries');
        localStorage.setItem(FREEFORM_KEY, freeform.value);
      }

      function restoreState() {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (!raw) return;
        try {
          JSON.parse(raw).forEach(id => {
            const cb = document.getElementById(id + '-checkbox');
            if (cb) cb.checked = true;
          });
        } catch(e) {
          console.error('Could not parse saved grocery state:', e);
        }
      }

      function restoreFreeform() {
        const saved = localStorage.getItem(FREEFORM_KEY);
        if (saved) {
          document.getElementById('freeform-entries').value = saved;
        }
      }

      function updateGroceryList() {
        // A Map: ingredientName → Set of recipe titles that need it
        const neededMap = new Map();

        // (a) from checked recipes
        document.querySelectorAll('input[type="checkbox"][data-ingredients]').forEach(cb => {
          if (!cb.checked) return;
          const recipeTitle = cb.dataset.title;
          const items = JSON.parse(cb.dataset.ingredients);
          items.forEach(name => {
            if (!neededMap.has(name)) neededMap.set(name, new Set());
            neededMap.get(name).add(recipeTitle);
          });
        });

        // (b) from the freeform textarea (we still want to show these, but they won't get a "Needed for")
        document.getElementById('freeform-entries').value
          .split(/\r?\n/)
          .map(l => l.trim())
          .filter(l => l)
          .forEach(name => {
            if (!neededMap.has(name)) neededMap.set(name, new Set());
          });

        // (c) show/hide & title for your static list items
        document
          .querySelectorAll('#grocery-list ul:not(#misc-items) li')
          .forEach(li => {
            const name = li.textContent.trim();
            const titles = neededMap.get(name);
            if (titles) {
              li.classList.add('is-needed-for-selected-recipes');
              if (titles.size > 0) {
                li.setAttribute(
                  'title',
                  'Needed for: ' + Array.from(titles).join(', ')
                );
              } else {
                li.removeAttribute('title');
              }
              neededMap.delete(name);
            } else {
              li.classList.remove('is-needed-for-selected-recipes');
              li.removeAttribute('title');
            }
          });

        // (d) dump everything else (leftovers) into Miscellaneous
        const misc = document.getElementById('misc-items');
        misc.innerHTML = '';
        neededMap.forEach((titles, name) => {
          const li = document.createElement('li');
          li.textContent = name;
          li.classList.add('is-needed-for-selected-recipes');
          if (titles.size > 0) {
            li.setAttribute(
              'title',
              'Needed for: ' + Array.from(titles).join(', ')
            );
          }
          misc.appendChild(li);
        });

        // (e) hide empty aisles
        document.querySelectorAll('#grocery-list div.aisle').forEach(aisle => {
          const hasVisibleItems = aisle.querySelectorAll('li.is-needed-for-selected-recipes').length > 0;
          aisle.classList.toggle('is-empty', !hasVisibleItems);
        });

        // (f) mark selected recipes for print styling
        document.querySelectorAll('#recipe-selector input[type="checkbox"][data-ingredients]').forEach(cb => {
          const li = cb.closest('li');
          li.classList.toggle('is-selected', cb.checked);
        });

        // (g) mark empty categories/subsections for print hiding
        document.querySelectorAll('#recipe-selector .category').forEach(cat => {
          const hasSelected = cat.querySelectorAll('li.is-selected').length > 0;
          cat.classList.toggle('is-empty', !hasSelected);
        });

        document.querySelectorAll('#recipe-selector .quick-bites .subsection').forEach(sub => {
          const hasSelected = sub.querySelectorAll('li.is-selected').length > 0;
          sub.classList.toggle('is-empty', !hasSelected);
        });

        const quickBites = document.querySelector('#recipe-selector .quick-bites');
        if (quickBites) {
          const hasAnySelected = quickBites.querySelectorAll('li.is-selected').length > 0;
          quickBites.classList.toggle('is-empty', !hasAnySelected);
        }

        // (h) update item count and empty state for preview
        const visibleItems = document.querySelectorAll('#grocery-list li.is-needed-for-selected-recipes');
        const itemCount = visibleItems.length;
        const countEl = document.getElementById('item-count');
        const emptyEl = document.getElementById('grocery-preview-empty');
        const groceryList = document.getElementById('grocery-list');

        if (itemCount > 0) {
          countEl.textContent = itemCount + (itemCount === 1 ? ' item' : ' items');
          emptyEl.style.display = 'none';
          groceryList.style.display = 'grid';
        } else {
          countEl.textContent = '';
          emptyEl.style.display = 'block';
          groceryList.style.display = 'none';
        }
      }

      document.addEventListener('DOMContentLoaded', () => {
        // reveal the JS-only bits
        document.querySelectorAll('.hidden-until-js')
                .forEach(el => el.classList.remove('hidden-until-js'));

        // wire up events
        const cbs = Array.from(
          document.querySelectorAll('input[type="checkbox"][data-ingredients]')
        );
        const freeform = document.getElementById('freeform-entries');

        cbs.forEach(cb => cb.addEventListener('change', () => {
          saveState();
          updateGroceryList();
        }));
        freeform.addEventListener('input', () => {
          saveFreeform();
          updateGroceryList();
        });

        // restore + initial draw
        restoreState();
        restoreFreeform();
        updateGroceryList();
      });
    })();
