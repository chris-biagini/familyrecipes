# frozen_string_literal: true

require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    ActionMailer::Base.deliveries.clear
    install_working_rate_limit_store
  end

  test 'GET /sessions/new renders the email form' do
    get new_session_path

    assert_response :success
    assert_select 'form[action=?]', sessions_path
    assert_select 'input[type=email][name=email]'
  end

  test 'GET /sessions/new redirects to root when already signed in' do
    log_in

    get new_session_path

    assert_redirected_to root_path
  end

  test 'POST /sessions with known email creates a magic link and delivers mail' do
    assert_difference -> { MagicLink.count } => 1, -> { ActionMailer::Base.deliveries.size } => 1 do
      post sessions_path, params: { email: @user.email }
    end

    assert_redirected_to sessions_magic_link_path

    link = MagicLink.order(:created_at).last

    assert_equal @user, link.user
    assert_equal 'sign_in', link.purpose
  end

  test 'POST /sessions with unknown email sends no mail but still redirects (anti-enumeration)' do
    assert_no_difference -> { MagicLink.count } do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        post sessions_path, params: { email: 'stranger@example.com' }
      end
    end

    assert_redirected_to sessions_magic_link_path
  end

  test 'POST /sessions with an email that matches a user with no memberships is treated as unknown' do
    orphan = ActsAsTenant.without_tenant do
      User.create!(name: 'Orphan', email: 'orphan@example.com')
    end
    orphan.memberships.destroy_all

    assert_no_difference -> { MagicLink.count } do
      post sessions_path, params: { email: orphan.email }
    end

    assert_redirected_to sessions_magic_link_path
  end

  test 'POST /sessions is rate-limited' do
    11.times { post sessions_path, params: { email: @user.email } }

    assert_response :too_many_requests
  end

  test 'POST /sessions sets the pending_auth cookie' do
    post sessions_path, params: { email: @user.email }

    assert_not_empty cookies[:pending_auth].to_s
  end

  private

  # Rails' `rate_limit` captures the configured cache store in its before_action
  # closure at class-load time. The test environment uses `:null_store`, which
  # discards increments, making the 429 path unreachable. Reach into the
  # captured closure and replace `store` with a fresh MemoryStore per test so
  # the counter actually counts and each test starts at zero.
  def install_working_rate_limit_store
    callback = SessionsController._process_action_callbacks.find do |cb|
      cb.kind == :before && cb.filter.is_a?(Proc) &&
        cb.filter.source_location&.first&.include?('rate_limiting')
    end
    return unless callback

    callback.filter.binding.local_variable_set(:store, ActiveSupport::Cache::MemoryStore.new)
  end
end
