# frozen_string_literal: true

# Production logout endpoint. Renders a sign-out interstitial showing the
# kitchen's join code(s) so the user can get back in. Loads kitchen data
# while still authenticated, then terminates the session before rendering.
#
# - Authentication concern: provides terminate_session, current_user
# - Kitchen: join_code for re-entry fallback
# - JoinsController: the "sign back in" link targets the join flow
class SessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path

  layout 'auth'

  def destroy
    unless authenticated?
      cookies[:skip_dev_auto_login] = true if Rails.env.development?
      return redirect_to root_path
    end

    @kitchen_codes = ActsAsTenant.without_tenant { kitchen_codes_for(current_user) }
    terminate_session
    cookies[:skip_dev_auto_login] = true if Rails.env.development?
  end

  private

  def kitchen_codes_for(user)
    user.kitchens.map { |k| { name: k.name, join_code: k.join_code } }
  end
end
