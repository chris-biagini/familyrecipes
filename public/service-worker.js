var CACHE_NAME = 'familyrecipes-v4';

var API_PATTERN = /^(\/kitchens\/[^/]+)?\/(groceries\/(state|check|custom_items|aisle_order|aisle_order_content)|menu\/(state|select|select_all|clear|quick_bites|quick_bites_content)|nutrition\/)/;

self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.add('/offline.html');
    })
  );
  self.skipWaiting();
});


self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(names) {
      return Promise.all(
        names.filter(function(name) {
          return name !== CACHE_NAME;
        }).map(function(name) {
          return caches.delete(name);
        })
      );
    }).then(function() {
      return self.clients.claim();
    })
  );
});

self.addEventListener('fetch', function(event) {
  if (event.request.method !== 'GET') return;

  var url = new URL(event.request.url);

  if (url.pathname === '/cable') return;

  if (API_PATTERN.test(url.pathname)) return;

  if (url.pathname.startsWith('/assets/')) {
    event.respondWith(cacheFirst(event.request));
    return;
  }

  if (url.pathname === '/manifest.json') {
    event.respondWith(networkFirstHTML(event.request));
    return;
  }

  if (url.pathname.startsWith('/icons/')) {
    event.respondWith(cacheFirst(event.request));
    return;
  }

  var accept = event.request.headers.get('accept') || '';
  if (accept.indexOf('text/html') !== -1) {
    event.respondWith(networkFirstHTML(event.request));
    return;
  }

  event.respondWith(cacheFirst(event.request));
});

function cacheFirst(request) {
  return caches.open(CACHE_NAME).then(function(cache) {
    return cache.match(request).then(function(cached) {
      if (cached) return cached;

      return fetch(request).then(function(response) {
        if (response.ok) {
          cache.put(request, response.clone());
        }
        return response;
      });
    });
  });
}

function networkFirstHTML(request) {
  return caches.open(CACHE_NAME).then(function(cache) {
    return fetch(request).then(function(response) {
      if (response.ok) {
        cache.put(request, response.clone());
      }
      return response;
    }).catch(function() {
      return cache.match(request).then(function(cached) {
        return cached || cache.match('/offline.html');
      });
    });
  });
}
