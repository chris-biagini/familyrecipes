# frozen_string_literal: true

require 'test_helper'

class ConnectedServiceTest < ActiveSupport::TestCase
  test 'links a provider identity to a user' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    service = user.connected_services.create!(provider: 'developer', uid: 'test@example.com')

    assert_equal 'developer', service.provider
    assert_equal user, service.user
  end

  test 'enforces unique provider + uid' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    user.connected_services.create!(provider: 'google', uid: '123')

    duplicate = ConnectedService.new(user: user, provider: 'google', uid: '123')

    refute_predicate duplicate, :valid?
  end

  test 'allows same uid across different providers' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    user.connected_services.create!(provider: 'google', uid: '123')

    different_provider = user.connected_services.new(provider: 'github', uid: '123')

    assert_predicate different_provider, :valid?
  end
end
