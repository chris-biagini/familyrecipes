# frozen_string_literal: true

# Production logout endpoint. Terminates the database-backed session and clears
# the signed cookie. Replaces DevSessionsController#destroy for production use.
#
# - Authentication concern: provides terminate_session
# - DevSessionsController: retains dev-only login (create action)
class SessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def destroy
    terminate_session
    cookies[:skip_dev_auto_login] = true if Rails.env.development?
    redirect_to root_path
  end
end
