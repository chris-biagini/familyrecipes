# frozen_string_literal: true

# Strict CSP: all directives use 'self' only, plus ws:/wss: for ActionCable
# and Google Fonts domains for style_src / font_src. Nonce generator uses the
# session ID so the bundled <script> tag and CodeMirror's runtime <style>
# injection pass their respective directives. No other inline styles. If you
# need to add external resources, update the policy here first.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, 'https://fonts.googleapis.com'
    policy.img_src     :self
    policy.font_src    :self, 'https://fonts.gstatic.com'
    # Bare ws:/wss: allows WebSocket connections to any host. Scoping to
    # self-equivalent origins would break ActionCable behind reverse proxies
    # that rewrite the Host header (common in homelab setups).
    policy.connect_src :self, 'ws:', 'wss:'
    policy.object_src  :none
    policy.frame_src   :none
    policy.base_uri    :self
    policy.form_action :self
  end

  # Session-based nonces (not per-request random) because Turbo Drive caches
  # page snapshots containing the nonce. A random nonce would invalidate every
  # cached snapshot on back-navigation.
  config.content_security_policy_nonce_generator = lambda { |request|
    request.session[:_nonce_init] ||= true
    request.session.id.to_s
  }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
