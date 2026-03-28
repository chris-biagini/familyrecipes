# frozen_string_literal: true

# rack-mini-profiler: always-on performance badge in development.
# Shows request timing, SQL query count, and memory usage on every page.
# Flamegraphs available via ?pp=flamegraph (requires stackprof gem).
#
# Collaborators:
# - content_security_policy.rb — session-based nonce reused here so the
#   injected <script> tag satisfies strict CSP
# - stackprof — provides flamegraph data when ?pp=flamegraph is requested
if defined?(Rack::MiniProfiler)
  Rack::MiniProfiler.config.tap do |c|
    c.position = 'bottom-left'
    c.content_security_policy_nonce = ->(env, headers) {
      ActionDispatch::Request.new(env).content_security_policy_nonce
    }
  end
end
