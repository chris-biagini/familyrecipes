# frozen_string_literal: true

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
