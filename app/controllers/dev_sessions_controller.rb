# frozen_string_literal: true

# Dev/test-only authentication bypass. Provides direct login at /dev/login/:id
# (blocked in production). Also handles /logout with a cookie that suppresses
# the auto-login-in-development flow, enabling logged-out experience testing.
class DevSessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :require_non_production_environment, only: :create

  def create
    user = User.find(params[:id])
    start_new_session_for(user)
    cookies.delete(:skip_dev_auto_login)
    kitchen = ActsAsTenant.without_tenant { user.kitchens.first }
    return redirect_to root_path unless kitchen

    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  def destroy
    terminate_session
    cookies[:skip_dev_auto_login] = true if Rails.env.development?
    redirect_to root_path
  end

  private

  def require_non_production_environment
    head :not_found unless Rails.env.local?
  end
end
