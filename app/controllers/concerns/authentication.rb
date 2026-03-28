# frozen_string_literal: true

# Auth-agnostic session management concern. Provides session resume from signed
# cookies, session creation (start_new_session_for), and termination. The "front
# door" that calls start_new_session_for varies by environment — trusted headers
# in production (Authelia), DevSessionsController in dev/test — but this concern
# doesn't care which one. ActionCable connections also authenticate through the
# same session cookie.
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
    end
  end

  def terminate_session
    Current.session&.destroy
    cookies.delete(:session_id)
    Current.reset
  end

  def current_user = Current.user
end
