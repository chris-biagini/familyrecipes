# frozen_string_literal: true

# Dev/test-only authentication bypass. Provides direct login at /dev/login/:id
# (blocked in production). Also exposes a Rails.cache reset endpoint used by
# the security pen test harness — rate limits are cache-backed with a 15-min
# window, which would otherwise leak between runs and break reruns.
#
# - SessionsController: production logout endpoint
# - Authentication concern: session lifecycle (start, terminate)
# - release_audit.rake: calls #reset_cache before running security specs
class DevSessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path
  skip_before_action :verify_authenticity_token, only: :reset_cache
  before_action :require_non_production_environment

  def create
    user = User.find(params[:id])
    start_new_session_for(user)
    kitchen = ActsAsTenant.without_tenant { user.kitchens.first }
    return redirect_to root_path unless kitchen

    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  def reset_cache
    Rails.cache.clear
    head :no_content
  end

  private

  def require_non_production_environment
    head :not_found unless Rails.env.local?
  end
end
