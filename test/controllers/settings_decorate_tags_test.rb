# frozen_string_literal: true

require 'test_helper'

class SettingsDecorateTagsTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
  end

  test 'show includes decorate_tags' do
    get settings_path(kitchen_slug:), headers: { 'Accept' => 'application/json' }

    data = response.parsed_body

    assert data.key?('decorate_tags')
    assert data['decorate_tags']
  end

  test 'update decorate_tags' do
    patch settings_path(kitchen_slug:),
          params: { kitchen: { decorate_tags: false } },
          headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
          as: :json

    assert_response :success
    assert_not @kitchen.reload.decorate_tags
  end
end
