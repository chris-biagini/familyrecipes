# frozen_string_literal: true

require 'test_helper'

class ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    setup_test_category
  end

  test 'create requires membership' do
    post import_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'create with no files redirects with flash' do
    log_in
    post import_path(kitchen_slug: kitchen_slug)

    assert_redirected_to home_path
    assert_match(/no importable files/i, flash[:notice])
  end
end
