# frozen_string_literal: true

# Serves the PWA manifest and service worker via Rails (not as static files)
# so they get Cache-Control: no-cache headers preventing proxy/CDN caching.
# Skips set_kitchen_from_path because these URLs are kitchen-agnostic.
#
# - Kitchen#site_title: manifest name resolved from the sole kitchen
# - pwa/service_worker.js.erb: minimal PWA-install stub (no caching)
class PwaController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def manifest
    response.headers['Cache-Control'] = 'no-cache'
    render json: manifest_data, content_type: 'application/manifest+json'
  end

  def service_worker
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Service-Worker-Allowed'] = '/'
    render template: 'pwa/service_worker', layout: false, content_type: 'application/javascript'
  end

  private

  def manifest_data
    {
      name: sole_kitchen_title,
      short_name: 'Recipes',
      start_url: '/',
      display: 'standalone',
      background_color: '#faf8f5',
      theme_color: '#faf8f5',
      icons: manifest_icons,
      shortcuts: [
        { name: 'Grocery List', short_name: 'Groceries', url: '/groceries' }
      ]
    }
  end

  def manifest_icons
    [
      icon_entry('icon-192.png', '192x192'),
      icon_entry('icon-512.png', '512x512'),
      icon_entry('icon-192-dark.png', '192x192', media: '(prefers-color-scheme: dark)'),
      icon_entry('icon-512-dark.png', '512x512', media: '(prefers-color-scheme: dark)')
    ]
  end

  def sole_kitchen_title
    kitchen = ActsAsTenant.without_tenant { Kitchen.first }
    kitchen&.site_title || 'mirepoix'
  end

  def icon_entry(filename, sizes, media: nil)
    entry = { src: versioned_icon_path(filename), sizes: sizes, type: 'image/png' }
    entry[:media] = media if media
    entry
  end
end
