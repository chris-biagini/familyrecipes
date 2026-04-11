# frozen_string_literal: true

require 'test_helper'

class KitchenAcceptingSignupsTest < ActiveSupport::TestCase
  setup do
    ActsAsTenant.without_tenant { Kitchen.delete_all }
    @original_disable = ENV.fetch('DISABLE_SIGNUPS', nil)
    @original_allow   = ENV.fetch('ALLOW_SIGNUPS', nil)
    ENV.delete('DISABLE_SIGNUPS')
    ENV.delete('ALLOW_SIGNUPS')
  end

  teardown do
    ENV['DISABLE_SIGNUPS'] = @original_disable
    ENV['ALLOW_SIGNUPS']   = @original_allow
  end

  test 'accepts signups on a fresh install with no env vars' do
    assert_predicate Kitchen, :accepting_signups?
  end

  test 'rejects signups after the first kitchen when no env vars are set' do
    create_kitchen_and_user

    assert_not Kitchen.accepting_signups?
  end

  test 'DISABLE_SIGNUPS=true wins even on a fresh install' do
    ENV['DISABLE_SIGNUPS'] = 'true'

    assert_not Kitchen.accepting_signups?
  end

  test 'ALLOW_SIGNUPS=true re-enables after the first kitchen' do
    create_kitchen_and_user
    ENV['ALLOW_SIGNUPS'] = 'true'

    assert_predicate Kitchen, :accepting_signups?
  end

  test 'DISABLE_SIGNUPS beats ALLOW_SIGNUPS' do
    create_kitchen_and_user
    ENV['ALLOW_SIGNUPS']   = 'true'
    ENV['DISABLE_SIGNUPS'] = 'true'

    assert_not Kitchen.accepting_signups?
  end
end
