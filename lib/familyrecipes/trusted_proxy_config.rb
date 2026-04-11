# frozen_string_literal: true

require 'ipaddr'

# Frozen config for trusted-header auth, parsed once from env vars at boot.
# Exposes a per-request peer IP check (allow?) and the Rack env keys for
# the configured header names. Built by a Rails initializer and read by
# ApplicationController#authenticate_from_headers — the controller never
# touches ENV directly.
#
# Defense-in-depth model: even if the reverse proxy is misconfigured and
# leaks inbound Remote-User headers from external requests, the peer IP
# check ignores them unless the TCP peer is in the allowlist. The loopback
# default (127.0.0.0/8 + ::1/128) covers same-host docker-compose installs
# zero-config; multi-host operators opt in by setting TRUSTED_PROXY_IPS.
# Empty string disables trusted-header auth entirely.
#
# Collaborators:
# - ApplicationController#authenticate_from_headers: per-request caller
# - config/initializers/trusted_proxy.rb: boot-time loader
# - config/initializers/trusted_proxy_warning.rb: production warning gate
module FamilyRecipes
  class TrustedProxyConfig
    DEFAULT_NETWORKS = '127.0.0.0/8,::1/128'

    class InvalidConfigError < StandardError; end

    def self.from_env(env = ENV)
      networks_raw = env.fetch('TRUSTED_PROXY_IPS', DEFAULT_NETWORKS)
      new(
        networks: parse_networks(networks_raw),
        user_header_name: env.fetch('TRUSTED_HEADER_USER', 'Remote-User'),
        email_header_name: env.fetch('TRUSTED_HEADER_EMAIL', 'Remote-Email'),
        name_header_name: env.fetch('TRUSTED_HEADER_NAME', 'Remote-Name'),
        default_networks: networks_raw == DEFAULT_NETWORKS
      ).freeze
    end

    def self.parse_networks(raw)
      return [] if raw.strip.empty?

      raw.split(',').map { |s| IPAddr.new(s.strip) }
    rescue IPAddr::Error => error
      raise InvalidConfigError, "TRUSTED_PROXY_IPS contains invalid CIDR: #{error.message}"
    end

    attr_reader :user_header, :email_header, :name_header

    def initialize(networks:, user_header_name:, email_header_name:, name_header_name:, default_networks:)
      @networks = networks.freeze
      @user_header = to_env_key(user_header_name)
      @email_header = to_env_key(email_header_name)
      @name_header = to_env_key(name_header_name)
      @default_networks = default_networks
    end

    def allow?(ip_string)
      return false if ip_string.blank?

      ip = IPAddr.new(ip_string)
      @networks.any? { |net| net.include?(ip) }
    rescue IPAddr::Error
      false
    end

    def default_networks?
      @default_networks
    end

    private

    def to_env_key(header_name)
      "HTTP_#{header_name.upcase.tr('-', '_')}"
    end
  end
end
