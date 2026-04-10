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

    travel 1.minute do
      get show_transfer_path(token:, k: kitchen_slug)

      assert_response :unprocessable_content
      assert_select '.auth-error'
    end
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

  test 'create_for_member requires authentication' do
    post member_login_link_path(id: @user.id)

    assert_response :forbidden
  end

  test 'create_for_member returns copyable link' do
    log_in
    other_user = User.create!(name: 'Other', email: 'other@example.com')
    ActsAsTenant.with_tenant(@kitchen) { Membership.create!(kitchen: @kitchen, user: other_user) }

    post member_login_link_path(id: other_user.id), params: { kitchen_slug: kitchen_slug }

    assert_response :success
    assert_select 'input[readonly]'
  end

  test 'create_for_member rejects caller who is not a kitchen member' do
    log_in
    other_kitchen = nil
    target = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other Kitchen', slug: 'other-kitchen')
      target = User.create!(name: 'Target', email: 'target@example.com')
      ActsAsTenant.with_tenant(other_kitchen) { Membership.create!(kitchen: other_kitchen, user: target) }
    end

    post member_login_link_path(id: target.id), params: { kitchen_slug: other_kitchen.slug }

    assert_response :forbidden
  end

  test 'create_for_member rejects non-member target' do
    log_in
    outsider = User.create!(name: 'Outsider', email: 'outsider@example.com')

    post member_login_link_path(id: outsider.id), params: { kitchen_slug: kitchen_slug }

    assert_response :not_found
  end

  test 'create_for_member token logs in target user' do
    log_in
    other_user = User.create!(name: 'Other', email: 'other@example.com')
    ActsAsTenant.with_tenant(@kitchen) { Membership.create!(kitchen: @kitchen, user: other_user) }

    post member_login_link_path(id: other_user.id), params: { kitchen_slug: kitchen_slug }

    link_input = css_select('input[readonly]').first
    url = link_input['value']
    reset!

    get url

    assert_response :redirect
    follow_redirect!

    assert_equal other_user.id, Session.last.user_id
  end
end
