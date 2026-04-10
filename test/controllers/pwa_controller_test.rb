# frozen_string_literal: true

require 'test_helper'

class PwaControllerTest < ActionDispatch::IntegrationTest
  test 'manifest returns JSON with versioned icon URLs' do
    get '/manifest.json'

    assert_response :success
    assert_equal 'application/manifest+json', response.media_type

    data = JSON.parse(response.body) # rubocop:disable Rails/ResponseParsedBody

    assert_equal 'Family Recipes', data['name']
    assert_equal 'Recipes', data['short_name']
    assert_equal '/', data['start_url']
    assert_equal 'standalone', data['display']
    assert_equal 4, data['icons'].size

    version = Rails.configuration.icon_version

    assert_equal "/icons/icon-192.png?v=#{version}", data['icons'][0]['src']
    assert_equal "/icons/icon-512.png?v=#{version}", data['icons'][1]['src']
    assert_nil data['icons'][0]['media']
    assert_nil data['icons'][1]['media']

    assert_equal "/icons/icon-192-dark.png?v=#{version}", data['icons'][2]['src']
    assert_equal "/icons/icon-512-dark.png?v=#{version}", data['icons'][3]['src']
    assert_equal '(prefers-color-scheme: dark)', data['icons'][2]['media']
    assert_equal '(prefers-color-scheme: dark)', data['icons'][3]['media']
  end

  test 'manifest includes dark mode icons with media attribute' do
    get '/manifest.json'

    data = JSON.parse(response.body) # rubocop:disable Rails/ResponseParsedBody

    dark_icons = data['icons'].select { |i| i['media'] }

    assert_equal 2, dark_icons.size

    dark_icons.each do |icon|
      assert_equal '(prefers-color-scheme: dark)', icon['media']
      assert_match(/-dark\.png/, icon['src'])
    end
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
