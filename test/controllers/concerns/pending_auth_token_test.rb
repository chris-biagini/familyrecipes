# frozen_string_literal: true

require 'test_helper'

class PendingAuthTokenTest < ActiveSupport::TestCase
  # Test the concern by including it into a PORO with stubbed cookies.
  class Harness
    include PendingAuthToken

    def initialize
      @cookie_store = {}
    end

    def cookies
      @cookies ||= CookieProxy.new(@cookie_store)
    end

    class CookieProxy
      delegate :[], :delete, to: :@store

      def initialize(store)
        @store = store
      end

      def signed
        self
      end

      def []=(key, value)
        @store[key] = value.is_a?(Hash) ? value[:value] : value
      end
    end
  end

  test 'set_pending_auth_email round-trips the email' do
    h = Harness.new
    h.set_pending_auth_email('chris@example.com')

    assert_equal 'chris@example.com', h.pending_auth_email
  end

  test 'pending_auth_email returns nil when unset' do
    assert_nil Harness.new.pending_auth_email
  end

  test 'pending_auth_email returns nil when tampered' do
    h = Harness.new
    h.cookies.signed[:pending_auth] = 'garbage'

    assert_nil h.pending_auth_email
  end

  test 'clear_pending_auth removes the cookie' do
    h = Harness.new
    h.set_pending_auth_email('chris@example.com')
    h.clear_pending_auth

    assert_nil h.pending_auth_email
  end
end
