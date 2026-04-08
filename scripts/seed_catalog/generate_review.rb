#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 3: Generate an interactive HTML review page from the enriched
# search results JSON. The page embeds the data and uses vanilla JS
# for review workflow, localStorage persistence, and JSON export.
#
# Usage: ruby scripts/seed_catalog/generate_review.rb

require_relative 'shared'

RESULTS_PATH = File.join(SeedCatalog::DATA_DIR, 'usda_search_results.json')
REVIEW_PATH = File.join(SeedCatalog::DATA_DIR, 'review.html')

AISLES = %w[
  Baking Beverages Bread Cereal Condiments Frozen Gourmet
  Health Household International Miscellaneous Pantry Personal
  Produce Refrigerated Snacks Specialty Spices
].freeze

def run
  data = SeedCatalog.read_json(RESULTS_PATH)
  abort 'No search results found. Run usda_search.rb first.' if data.empty?

  without_picks = data.count { |d| d['ai_pick'].nil? }
  warn "Warning: #{without_picks}/#{data.size} ingredients have no AI pick yet." if without_picks.positive?

  html = build_html(data)
  File.write(REVIEW_PATH, html)
  puts "Review page written to #{REVIEW_PATH} (#{data.size} ingredients)"
end

def build_html(data)
  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <title>Seed Catalog Review</title>
    <style>
    #{css}
    </style>
    </head>
    <body>
    <h1>Seed Catalog Review</h1>
    <div class="controls">
      <label>Category: <select id="cat-filter"><option value="">All</option></select></label>
      <label>Status: <select id="status-filter">
        <option value="">All</option>
        <option value="pending">Pending</option>
        <option value="accept">Accepted</option>
        <option value="override">Override</option>
        <option value="skip">Skip</option>
        <option value="manual">Manual</option>
      </select></label>
      <span id="stats"></span>
      <button id="export-btn">Export Decisions</button>
      <button id="clear-btn">Clear All Decisions</button>
    </div>
    <table>
    <thead><tr>
      <th class="col-name">Ingredient</th>
      <th class="col-cat">Category</th>
      <th class="col-pick">AI Pick</th>
      <th class="col-reason">Reasoning</th>
      <th class="col-alts">Alternatives</th>
      <th class="col-aisle">Aisle</th>
      <th class="col-aliases">Aliases</th>
      <th class="col-status">Status</th>
      <th class="col-override">Override FDC ID</th>
      <th class="col-notes">Notes</th>
    </tr></thead>
    <tbody id="tbody"></tbody>
    </table>

    <script type="application/json" id="ingredient-data">
    #{JSON.generate(data)}
    </script>
    <script type="application/json" id="aisle-list">
    #{JSON.generate(AISLES)}
    </script>
    <script>
    #{javascript}
    </script>
    </body>
    </html>
  HTML
end

def css
  <<~CSS
    * { box-sizing: border-box; }
    body {
      font-family: system-ui, sans-serif; margin: 0 auto;
      padding: 16px; max-width: 1600px; font-size: 14px;
    }
    h1 { margin: 0 0 12px; }
    .controls {
      display: flex; align-items: center; gap: 12px;
      margin-bottom: 12px; flex-wrap: wrap;
    }
    .controls label { font-weight: 500; }
    #stats { margin-left: auto; color: #555; }
    button { padding: 6px 14px; cursor: pointer; }
    table { border-collapse: collapse; width: 100%; }
    th, td {
      border: 1px solid #ccc; padding: 6px 8px;
      text-align: left; vertical-align: top;
    }
    th { background: #f0f0f0; position: sticky; top: 0; z-index: 1; }
    .col-name { min-width: 140px; font-weight: 600; }
    .col-cat { min-width: 100px; }
    .col-pick { min-width: 200px; }
    .col-reason { min-width: 140px; font-size: 13px; color: #555; }
    .col-alts { min-width: 200px; font-size: 13px; }
    .col-aisle { min-width: 100px; }
    .col-aliases { min-width: 120px; }
    .col-status { min-width: 90px; }
    .col-override { min-width: 100px; }
    .col-notes { min-width: 100px; }
    a { color: #0066cc; }
    tr[data-status="accept"] { background: #e8f5e9; }
    tr[data-status="skip"] { background: #fce4ec; }
    tr[data-status="manual"] { background: #fff3e0; }
    tr[data-status="override"] { background: #e3f2fd; }
    select, input { padding: 4px; font-size: 13px; }
    td input[type="text"] { width: 100%; }
    td input[type="number"] { width: 80px; }
    .alt-link { display: block; margin: 2px 0; }
    .no-pick { color: #999; font-style: italic; }
  CSS
end

def javascript
  <<~'JS'
    (function() {
      var data = JSON.parse(document.getElementById('ingredient-data').textContent);
      var aisles = JSON.parse(document.getElementById('aisle-list').textContent);
      var STORAGE_KEY = 'seed_catalog_review';
      var decisions = loadDecisions();
      var tbody = document.getElementById('tbody');
      var catFilter = document.getElementById('cat-filter');
      var statusFilter = document.getElementById('status-filter');

      initCategoryFilter();
      renderTable();
      updateStats();

      catFilter.addEventListener('change', renderTable);
      statusFilter.addEventListener('change', renderTable);
      document.getElementById('export-btn').addEventListener('click', exportDecisions);
      document.getElementById('clear-btn').addEventListener('click', function() {
        if (confirm('Clear all review decisions?')) {
          decisions = {};
          localStorage.removeItem(STORAGE_KEY);
          renderTable();
          updateStats();
        }
      });

      function usdaLink(fdcId) {
        return 'https://fdc.nal.usda.gov/food-details/' + fdcId + '/nutrients';
      }

      function initCategoryFilter() {
        var cats = [];
        data.forEach(function(d) {
          if (d.category && cats.indexOf(d.category) === -1) cats.push(d.category);
        });
        cats.sort().forEach(function(c) {
          var opt = document.createElement('option');
          opt.value = c;
          opt.textContent = c;
          catFilter.appendChild(opt);
        });
      }

      function getDecision(name) {
        return decisions[name] || {
          status: 'pending', override_fdc_id: '', aisle: '', aliases: '', notes: ''
        };
      }

      function setDecision(name, field, value) {
        if (!decisions[name]) {
          decisions[name] = {
            status: 'pending', override_fdc_id: '', aisle: '', aliases: '', notes: ''
          };
        }
        decisions[name][field] = value;
        localStorage.setItem(STORAGE_KEY, JSON.stringify(decisions));
        updateStats();
      }

      function renderTable() {
        while (tbody.firstChild) tbody.removeChild(tbody.firstChild);
        var catVal = catFilter.value;
        var statusVal = statusFilter.value;
        data.forEach(function(item) {
          var dec = getDecision(item.name);
          if (catVal && item.category !== catVal) return;
          if (statusVal && dec.status !== statusVal) return;
          tbody.appendChild(buildRow(item, dec));
        });
      }

      function buildRow(item, dec) {
        var tr = document.createElement('tr');
        tr.setAttribute('data-status', dec.status);

        addCell(tr, item.name);
        addCell(tr, item.category || '');
        addPickCell(tr, item);
        addCell(tr, (item.ai_pick && item.ai_pick.reasoning) || '');
        addAltsCell(tr, item);
        addAisleCell(tr, item, dec);
        addInputCell(tr, item, dec, 'aliases', (item.aliases || []).join(', '));
        addStatusCell(tr, item, dec);
        addOverrideCell(tr, item, dec);
        addInputCell(tr, item, dec, 'notes', '');

        return tr;
      }

      function addCell(tr, text) {
        var td = document.createElement('td');
        td.textContent = text;
        tr.appendChild(td);
      }

      function addPickCell(tr, item) {
        var td = document.createElement('td');
        if (item.ai_pick) {
          var a = document.createElement('a');
          a.href = usdaLink(item.ai_pick.fdc_id);
          a.target = '_blank';
          var desc = findDesc(item, item.ai_pick.fdc_id) || 'Unknown';
          a.textContent = item.ai_pick.fdc_id + ': ' + desc;
          td.appendChild(a);
        } else {
          var span = document.createElement('span');
          span.className = 'no-pick';
          span.textContent = 'No AI pick';
          td.appendChild(span);
        }
        tr.appendChild(td);
      }

      function addAltsCell(tr, item) {
        var td = document.createElement('td');
        (item.usda_results || []).forEach(function(r) {
          if (item.ai_pick && r.fdc_id === item.ai_pick.fdc_id) return;
          var a = document.createElement('a');
          a.href = usdaLink(r.fdc_id);
          a.target = '_blank';
          a.className = 'alt-link';
          var label = r.fdc_id + ': ' + r.description;
          if (r.dataset) label += ' [' + r.dataset + ']';
          a.textContent = label;
          td.appendChild(a);
        });
        tr.appendChild(td);
      }

      function addAisleCell(tr, item, dec) {
        var td = document.createElement('td');
        var sel = document.createElement('select');
        var empty = document.createElement('option');
        empty.value = '';
        empty.textContent = '\u2014';
        sel.appendChild(empty);
        aisles.forEach(function(a) {
          var opt = document.createElement('option');
          opt.value = a;
          opt.textContent = a;
          sel.appendChild(opt);
        });
        sel.value = dec.aisle || item.aisle || '';
        sel.addEventListener('change', function() {
          setDecision(item.name, 'aisle', this.value);
        });
        td.appendChild(sel);
        tr.appendChild(td);
      }

      function addInputCell(tr, item, dec, field, fallback) {
        var td = document.createElement('td');
        var input = document.createElement('input');
        input.type = 'text';
        input.value = dec[field] || fallback;
        input.addEventListener('change', function() {
          setDecision(item.name, field, this.value);
        });
        td.appendChild(input);
        tr.appendChild(td);
      }

      function addStatusCell(tr, item, dec) {
        var td = document.createElement('td');
        var sel = document.createElement('select');
        ['pending', 'accept', 'override', 'skip', 'manual'].forEach(function(s) {
          var opt = document.createElement('option');
          opt.value = s;
          opt.textContent = s.charAt(0).toUpperCase() + s.slice(1);
          sel.appendChild(opt);
        });
        sel.value = dec.status;
        sel.addEventListener('change', function() {
          setDecision(item.name, 'status', this.value);
          tr.setAttribute('data-status', this.value);
        });
        td.appendChild(sel);
        tr.appendChild(td);
      }

      function addOverrideCell(tr, item, dec) {
        var td = document.createElement('td');
        var input = document.createElement('input');
        input.type = 'number';
        input.value = dec.override_fdc_id || '';
        input.placeholder = 'FDC ID';
        input.addEventListener('change', function() {
          setDecision(item.name, 'override_fdc_id', this.value);
        });
        td.appendChild(input);
        tr.appendChild(td);
      }

      function findDesc(item, fdcId) {
        var match = (item.usda_results || []).filter(function(r) {
          return r.fdc_id === fdcId;
        });
        return match.length > 0 ? match[0].description : null;
      }

      function updateStats() {
        var total = data.length;
        var counts = { pending: 0, accept: 0, override: 0, skip: 0, manual: 0 };
        data.forEach(function(d) {
          var s = getDecision(d.name).status;
          counts[s] = (counts[s] || 0) + 1;
        });
        var reviewed = total - counts.pending;
        document.getElementById('stats').textContent =
          reviewed + '/' + total + ' reviewed | ' +
          counts.accept + ' accepted, ' + counts.override + ' override, ' +
          counts.skip + ' skip, ' + counts.manual + ' manual';
      }

      function loadDecisions() {
        try {
          var stored = localStorage.getItem(STORAGE_KEY);
          return stored ? JSON.parse(stored) : {};
        } catch(e) { return {}; }
      }

      function exportDecisions() {
        var exported = data.map(function(item) {
          var dec = getDecision(item.name);
          var out = JSON.parse(JSON.stringify(item));
          out.review = {
            status: dec.status,
            override_fdc_id: dec.override_fdc_id
              ? parseInt(dec.override_fdc_id, 10) : null,
            aisle: dec.aisle || item.aisle || null,
            aliases: dec.aliases
              ? dec.aliases.split(',').map(function(s) {
                  return s.trim();
                }).filter(Boolean)
              : (item.aliases || []),
            notes: dec.notes || null
          };
          return out;
        });
        var blob = new Blob(
          [JSON.stringify(exported, null, 2)],
          { type: 'application/json' }
        );
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = 'reviewed_results.json';
        a.click();
        URL.revokeObjectURL(a.href);
      }
    })();
  JS
end

run if $PROGRAM_NAME == __FILE__
