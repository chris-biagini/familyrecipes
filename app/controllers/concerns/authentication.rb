# frozen_string_literal: true

# Auth-agnostic session management concern. Provides session resume from signed
# cookies, session creation (start_new_session_for), and termination. The "front
# door" that calls start_new_session_for varies by environment — magic-link
# sign-in and join-code flows in production, DevSessionsController in dev/test
# — but this concern doesn't care which one. ActionCable connections also
# authenticate through the same session cookie.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated? = Current.session.present?

  def require_authentication
    resume_session || head(:forbidden)
  end

  def resume_session
    Current.session ||= find_session_by_cookie
    warn_on_session_drift if Current.session
    Current.session
  end

  def find_session_by_cookie
    Session.find_by(id: cookies.signed[:session_id])
  end

  def start_new_session_for(user)
    user.sessions.create!(
      user_agent: request.user_agent,
      ip_address: request.remote_ip
    ).tap do |new_session|
      Current.session = new_session
      cookies.signed.permanent[:session_id] = {
        value: new_session.id, httponly: true, same_site: :lax, secure: Rails.env.production?
      }
      SecurityEventLogger.log(:session_created, session_id: new_session.id, user_id: user.id)
    end
  end

  def terminate_session
    if Current.session
      SecurityEventLogger.log(:session_destroyed, session_id: Current.session.id)
      Current.session.destroy
    end
    cookies.delete(:session_id)
    Current.reset
  end

  def warn_on_session_drift
    return unless Current.session

    ip_changed = Current.session.ip_address != request.remote_ip
    ua_changed = Current.session.user_agent != request.user_agent
    return unless ip_changed || ua_changed

    SecurityEventLogger.log(:session_drift,
                            session_id: Current.session.id,
                            ip_changed: ip_changed, ua_changed: ua_changed)
  end

  def current_user = Current.user
end
