# frozen_string_literal: true

require 'test_helper'

class SessionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: 'Test', email: 'test@example.com')
  end

  test 'belongs to user' do
    session = @user.sessions.create!(ip_address: '127.0.0.1', user_agent: 'Minitest')

    assert_equal @user, session.user
  end

  test 'Current.user delegates through session' do
    session = @user.sessions.create!(ip_address: '127.0.0.1', user_agent: 'Minitest')

    Current.session = session

    assert_equal @user, Current.user
  ensure
    Current.reset
  end

  test "sets expires_at on creation" do
    session = Session.create!(user: @user)

    assert_in_delta 30.days.from_now, session.expires_at, 1.minute
  end

  test "active scope excludes expired sessions" do
    active = Session.create!(user: @user)
    expired = Session.create!(user: @user, expires_at: 1.hour.ago)

    assert_includes Session.active.to_a, active
    assert_not_includes Session.active.to_a, expired
  end

  test "cleanup_stale deletes expired sessions" do
    Session.create!(user: @user)
    Session.create!(user: @user, expires_at: 1.hour.ago)

    assert_difference 'Session.count', -1 do
      Session.cleanup_stale
    end
  end
end
