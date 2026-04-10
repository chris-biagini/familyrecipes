# frozen_string_literal: true

# Production-only startup nudge for operators running with the default
# loopback-only trusted-proxy allowlist. If the reverse proxy is on the
# same host / same container, loopback is correct and this warning is
# noise you can ignore. If the proxy is on a separate host or a
# different docker network, the default ignores trusted headers from
# your proxy — you need to set TRUSTED_PROXY_IPS to the proxy's CIDR.
#
# Does not hard-fail boot: there are too many valid topologies to guess
# a safe universal default. Does not fire in development or test.
# See README "Trust model" for the full hardening story.
if Rails.env.production? && Rails.application.config.trusted_proxy_config.default_networks?
  Rails.logger.warn(
    'TRUSTED_PROXY_IPS is at the loopback-only default (127.0.0.0/8,::1/128). ' \
    'If your reverse proxy is not on the same host, set TRUSTED_PROXY_IPS to ' \
    "the proxy's CIDR range(s). To disable trusted-header auth entirely, set " \
    'TRUSTED_PROXY_IPS= (empty). See README for details.'
  )
end
