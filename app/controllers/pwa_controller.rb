# frozen_string_literal: true

# Serves the PWA manifest and service worker via Rails (not as static files)
# so they can use ERB and get Cache-Control: no-cache headers. This prevents
# Cloudflare from edge-caching them with the static file TTL. Skips
# set_kitchen_from_path because these URLs are kitchen-agnostic.
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
      name: Rails.configuration.site.site_title,
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
