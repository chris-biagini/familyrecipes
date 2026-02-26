# frozen_string_literal: true

class PwaController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def manifest
    render json: manifest_data, content_type: 'application/manifest+json'
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
