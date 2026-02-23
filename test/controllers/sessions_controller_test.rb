# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test 'login page renders successfully' do
    get login_path

    assert_response :success
    assert_select 'h1', 'Log In'
  end

  test 'login page has form that posts to omniauth developer' do
    get login_path

    assert_select 'form[action="/auth/developer/callback"][method="post"]'
    assert_select 'input[name="name"]'
    assert_select 'input[name="email"]'
  end

  test 'unauthenticated access to protected action redirects to login' do
    create_kitchen_and_user

    post recipes_path(kitchen_slug: kitchen_slug), params: { recipe: { markdown: '# Test' } }

    assert_redirected_to login_path
  end
end
