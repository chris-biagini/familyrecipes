# frozen_string_literal: true

require 'test_helper'

class TransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'show with valid transfer token creates session and redirects' do
    token = @user.signed_id(purpose: :transfer, expires_in: 5.minutes)

    get show_transfer_path(token:, k: kitchen_slug)

    assert_redirected_to kitchen_root_path(kitchen_slug: kitchen_slug)
    assert_predicate cookies[:session_id], :present?
  end

  test 'show with valid login token creates session and redirects' do
    token = @user.signed_id(purpose: :login, expires_in: 24.hours)

    get show_transfer_path(token:, k: kitchen_slug)

    assert_redirected_to kitchen_root_path(kitchen_slug: kitchen_slug)
    assert_predicate cookies[:session_id], :present?
  end

  test 'show with expired token renders error' do
    token = @user.signed_id(purpose: :transfer, expires_in: 0.seconds)
    travel 1.minute

    get show_transfer_path(token:, k: kitchen_slug)

    assert_response :unprocessable_content
    assert_select '.auth-error'
  end

  test 'show with tampered token renders error' do
    get show_transfer_path(token: 'tampered-garbage', k: kitchen_slug)

    assert_response :unprocessable_content
    assert_select '.auth-error'
  end

  test 'show with wrong kitchen slug renders error' do
    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    token = @user.signed_id(purpose: :transfer, expires_in: 5.minutes)

    get show_transfer_path(token:, k: other_kitchen.slug)

    assert_response :unprocessable_content
    assert_select '.auth-error'
  end

  test 'create requires authentication' do
    post create_transfer_path

    assert_response :forbidden
  end

  test 'create returns QR code and link' do
    log_in

    post create_transfer_path, params: { kitchen_slug: kitchen_slug }

    assert_response :success
    assert_select 'svg'
    assert_select 'input[readonly]'
  end

  test 'create token is consumable' do
    log_in

    post create_transfer_path, params: { kitchen_slug: kitchen_slug }

    link_input = css_select('input[readonly]').first
    url = link_input['value']
    reset!

    get url

    assert_response :redirect
    assert_predicate cookies[:session_id], :present?
  end
end
