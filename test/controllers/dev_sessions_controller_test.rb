# frozen_string_literal: true

require 'test_helper'

class DevSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'login sets session and redirects to kitchen' do
    get dev_login_path(id: @user.id)

    assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)
  end

  test 'reset_cache clears Rails.cache and returns 204' do
    Rails.cache.write('sentinel', 'x')

    delete dev_reset_cache_path

    assert_response :no_content
    assert_nil Rails.cache.read('sentinel')
  end
end
