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

    assert_select 'form[action="/auth/developer"][method="post"]'
    assert_select 'input[name="name"]'
    assert_select 'input[name="email"]'
  end
end
