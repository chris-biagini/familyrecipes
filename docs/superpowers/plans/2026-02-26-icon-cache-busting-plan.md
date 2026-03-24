# Icon Cache-Busting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add content-based cache-busting query strings to all PWA icon references so iOS (and other aggressive caches) fetch fresh icons when the source SVG changes.

**Architecture:** Compute a short SHA256 hash of `favicon.svg` at boot time, store it in `Rails.configuration.icon_version`. Expose a `versioned_icon_path` helper on ApplicationController. Convert the static `public/manifest.json` to a Rails-served route via `PwaController#manifest`. Update the service worker to fetch the manifest network-first (icons stay cache-first — query string changes produce new cache keys).

**Tech Stack:** Rails initializer, controller, service worker (vanilla JS)

---

### Task 1: Add icon version initializer

**Files:**
- Create: `config/initializers/icon_version.rb`

**Step 1: Create the initializer**

```ruby
# frozen_string_literal: true

Rails.configuration.icon_version = begin
  svg = Rails.root.join('app/assets/images/favicon.svg')
  svg.exist? ? Digest::SHA256.file(svg).hexdigest[0, 8] : '0'
end
```

**Step 2: Verify in console**

Run: `bin/rails runner "puts Rails.configuration.icon_version"`
Expected: an 8-character hex string (e.g., `a1b2c3d4`)

**Step 3: Commit**

```bash
git add config/initializers/icon_version.rb
git commit -m "feat: compute icon version hash from favicon.svg at boot"
```

---

### Task 2: Add versioned_icon_path helper and PwaController

**Files:**
- Modify: `app/controllers/application_controller.rb:18` (add to helper_method list)
- Modify: `app/controllers/application_controller.rb` (add method before `set_kitchen_from_path`)
- Create: `app/controllers/pwa_controller.rb`
- Modify: `config/routes.rb` (add manifest route)
- Delete: `public/manifest.json`
- Create: `test/controllers/pwa_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true

require 'test_helper'

class PwaControllerTest < ActionDispatch::IntegrationTest
  test 'manifest returns JSON with versioned icon URLs' do
    get '/manifest.json'

    assert_response :success
    assert_equal 'application/manifest+json', response.media_type

    data = JSON.parse(response.body)
    assert_equal 'Biagini Family Recipes', data['name']
    assert_equal 'Recipes', data['short_name']
    assert_equal '/', data['start_url']
    assert_equal 'standalone', data['display']
    assert_equal 2, data['icons'].size

    version = Rails.configuration.icon_version
    assert_equal "/icons/icon-192.png?v=#{version}", data['icons'][0]['src']
    assert_equal "/icons/icon-512.png?v=#{version}", data['icons'][1]['src']
  end

  test 'manifest works without any kitchen' do
    get '/manifest.json'

    assert_response :success
  end

  test 'manifest works with multiple kitchens' do
    Kitchen.create!(name: 'Kitchen A', slug: 'kitchen-a')
    Kitchen.create!(name: 'Kitchen B', slug: 'kitchen-b')

    get '/manifest.json'

    assert_response :success
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/pwa_controller_test.rb`
Expected: FAIL — route not found

**Step 3: Add `versioned_icon_path` to ApplicationController**

In `app/controllers/application_controller.rb`, change line 18 from:
```ruby
  helper_method :current_kitchen, :logged_in?, :home_path
```
to:
```ruby
  helper_method :current_kitchen, :logged_in?, :home_path, :versioned_icon_path
```

Add this method in the private section (after `home_path`, before `authenticate_from_headers`):
```ruby
  def versioned_icon_path(filename)
    "/icons/#{filename}?v=#{Rails.configuration.icon_version}"
  end
```

**Step 4: Create PwaController**

```ruby
# frozen_string_literal: true

class PwaController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def manifest
    render json: manifest_data, content_type: 'application/manifest+json'
  end

  private

  def manifest_data
    {
      name: Rails.configuration.site.fetch('site_title'),
      short_name: 'Recipes',
      start_url: '/',
      display: 'standalone',
      background_color: '#ffffff',
      theme_color: '#cd4754',
      icons: [
        { src: versioned_icon_path('icon-192.png'), sizes: '192x192', type: 'image/png' },
        { src: versioned_icon_path('icon-512.png'), sizes: '512x512', type: 'image/png' }
      ],
      shortcuts: [
        { name: 'Grocery List', short_name: 'Groceries', url: '/groceries' }
      ]
    }
  end
end
```

**Step 5: Add route and delete static manifest**

In `config/routes.rb`, add after line 4 (`get 'up'`):
```ruby
  get 'manifest.json', to: 'pwa#manifest', as: :pwa_manifest
```

Delete `public/manifest.json` (Rails will serve the route instead).

**Step 6: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/pwa_controller_test.rb`
Expected: 3 tests, 0 failures

**Step 7: Commit**

```bash
git add app/controllers/application_controller.rb app/controllers/pwa_controller.rb \
  config/routes.rb test/controllers/pwa_controller_test.rb
git rm public/manifest.json
git commit -m "feat: serve manifest.json from PwaController with versioned icon URLs"
```

---

### Task 3: Update layout to use versioned icon paths

**Files:**
- Modify: `app/views/layouts/application.html.erb:11-12`

**Step 1: Update the link tags**

In `app/views/layouts/application.html.erb`, change lines 11-12 from:
```erb
  <link rel="icon" type="image/png" sizes="32x32" href="/icons/favicon-32.png">
  <link rel="apple-touch-icon" sizes="180x180" href="/icons/apple-touch-icon.png">
```
to:
```erb
  <link rel="icon" type="image/png" sizes="32x32" href="<%= versioned_icon_path('favicon-32.png') %>">
  <link rel="apple-touch-icon" sizes="180x180" href="<%= versioned_icon_path('apple-touch-icon.png') %>">
```

**Step 2: Verify with an existing test**

Run: `ruby -Itest test/controllers/landing_controller_test.rb`
Expected: PASS (existing tests still work — they don't assert icon hrefs)

**Step 3: Verify visually**

Start `bin/dev`, view page source, confirm icon links include `?v=<hash>`.

**Step 4: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat: use versioned icon paths in layout for cache busting"
```

---

### Task 4: Update service worker — manifest network-first, bump cache version

**Files:**
- Modify: `public/service-worker.js:1` (bump CACHE_NAME)
- Modify: `public/service-worker.js:45-48` (split icons/manifest caching strategy)

**Step 1: Bump CACHE_NAME**

In `public/service-worker.js`, change line 1 from:
```js
var CACHE_NAME = 'familyrecipes-v2';
```
to:
```js
var CACHE_NAME = 'familyrecipes-v3';
```

**Step 2: Split manifest from icons caching**

Change lines 45-48 from:
```js
  if (url.pathname.startsWith('/icons/') || url.pathname === '/manifest.json') {
    event.respondWith(cacheFirst(event.request));
    return;
  }
```
to:
```js
  if (url.pathname === '/manifest.json') {
    event.respondWith(networkFirstHTML(event.request));
    return;
  }

  if (url.pathname.startsWith('/icons/')) {
    event.respondWith(cacheFirst(event.request));
    return;
  }
```

Note: `networkFirstHTML` works fine here — if the manifest cache misses and the network is down, the offline.html fallback is harmless (the manifest is only fetched when the browser needs it, not on every navigation).

**Step 3: Commit**

```bash
git add public/service-worker.js
git commit -m "fix: serve manifest network-first and bump SW cache for icon versioning"
```

---

### Task 5: Run full test suite and verify

**Step 1: Run lint**

Run: `rake lint`
Expected: no new offenses

**Step 2: Run full test suite**

Run: `rake test`
Expected: all tests pass

**Step 3: Manual verification**

Start `bin/dev` and verify:
1. View page source — apple-touch-icon and favicon-32 have `?v=<hash>` query strings
2. Fetch `/manifest.json` — returns JSON with versioned icon `src` fields
3. Confirm service worker updates (check DevTools > Application > Service Workers)
4. Confirm no regressions on recipe pages, groceries, etc.
