# frozen_string_literal: true

require 'test_helper'

class SessionTest < ActiveSupport::TestCase
  test 'belongs to user' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    session = user.sessions.create!(ip_address: '127.0.0.1', user_agent: 'Minitest')

    assert_equal user, session.user
  end

  test 'Current.user delegates through session' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    session = user.sessions.create!(ip_address: '127.0.0.1', user_agent: 'Minitest')

    Current.session = session

    assert_equal user, Current.user
  ensure
    Current.reset
  end
end
