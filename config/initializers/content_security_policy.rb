# frozen_string_literal: true

# Strict CSP: all directives use 'self' only, plus ws:/wss: for ActionCable.
# Nonce generator uses the session ID so importmap-rails' inline <script> tags
# pass script-src. No inline styles, no external resources. If you need to add
# any of these, update the policy here first.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self
    policy.img_src     :self
    policy.font_src    :self
    policy.connect_src :self, 'ws:', 'wss:'
    policy.object_src  :none
    policy.frame_src   :none
    policy.base_uri    :self
    policy.form_action :self
  end

  # Force session initialization so the ID is never nil on first cookieless request
  config.content_security_policy_nonce_generator = lambda { |request|
    request.session[:_nonce_init] ||= true
    request.session.id.to_s
  }
  config.content_security_policy_nonce_directives = %w[script-src]
end
