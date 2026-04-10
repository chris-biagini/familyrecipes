# frozen_string_literal: true

require 'test_helper'

class TrustedProxyConfigTest < ActiveSupport::TestCase
  Config = FamilyRecipes::TrustedProxyConfig

  test 'from_env uses loopback default when TRUSTED_PROXY_IPS is unset' do
    cfg = Config.from_env({})

    assert cfg.allow?('127.0.0.1')
    assert cfg.allow?('127.5.5.5')
    assert cfg.allow?('::1')
    assert_not cfg.allow?('10.0.0.1')
    assert_not cfg.allow?('203.0.113.5')
    assert_predicate cfg, :default_networks?
  end

  test 'from_env parses comma-separated CIDR list with whitespace tolerance' do
    cfg = Config.from_env('TRUSTED_PROXY_IPS' => '10.0.0.0/24, 192.168.1.0/24 ,172.16.0.0/16')

    assert cfg.allow?('10.0.0.5')
    assert cfg.allow?('192.168.1.200')
    assert cfg.allow?('172.16.5.5')
    assert_not cfg.allow?('127.0.0.1')
    assert_not cfg.default_networks?
  end

  test 'from_env parses IPv6 CIDRs' do
    cfg = Config.from_env('TRUSTED_PROXY_IPS' => 'fd00::/8')

    assert cfg.allow?('fd12:3456::1')
    assert_not cfg.allow?('2001:db8::1')
  end

  test 'from_env with empty TRUSTED_PROXY_IPS string produces empty allowlist' do
    cfg = Config.from_env('TRUSTED_PROXY_IPS' => '')

    assert_not cfg.allow?('127.0.0.1')
    assert_not cfg.allow?('10.0.0.1')
    assert_not cfg.default_networks?
  end

  test 'allow? returns false for blank input' do
    cfg = Config.from_env({})

    assert_not cfg.allow?(nil)
    assert_not cfg.allow?('')
  end

  test 'allow? returns false for malformed IP strings' do
    cfg = Config.from_env({})

    assert_not cfg.allow?('not-an-ip')
    assert_not cfg.allow?('999.999.999.999')
  end

  test 'header name env vars map to Rack env keys with HTTP_ prefix and underscores' do
    cfg = Config.from_env(
      'TRUSTED_HEADER_USER' => 'X-Webauth-User',
      'TRUSTED_HEADER_EMAIL' => 'X-Webauth-Email',
      'TRUSTED_HEADER_NAME' => 'X-Webauth-Name'
    )

    assert_equal 'HTTP_X_WEBAUTH_USER', cfg.user_header
    assert_equal 'HTTP_X_WEBAUTH_EMAIL', cfg.email_header
    assert_equal 'HTTP_X_WEBAUTH_NAME', cfg.name_header
  end

  test 'header name defaults map to Remote-* Rack env keys' do
    cfg = Config.from_env({})

    assert_equal 'HTTP_REMOTE_USER', cfg.user_header
    assert_equal 'HTTP_REMOTE_EMAIL', cfg.email_header
    assert_equal 'HTTP_REMOTE_NAME', cfg.name_header
  end

  test 'invalid CIDR raises InvalidConfigError with a clear message' do
    error = assert_raises(Config::InvalidConfigError) do
      Config.from_env('TRUSTED_PROXY_IPS' => '10.0.0.0/99')
    end

    assert_match(/TRUSTED_PROXY_IPS/, error.message)
  end

  test 'default_networks? is true only when TRUSTED_PROXY_IPS matches the default verbatim' do
    assert_predicate Config.from_env({}), :default_networks?
    assert_predicate Config.from_env('TRUSTED_PROXY_IPS' => Config::DEFAULT_NETWORKS), :default_networks?
    assert_not_predicate Config.from_env('TRUSTED_PROXY_IPS' => '127.0.0.0/8'), :default_networks?
  end
end
