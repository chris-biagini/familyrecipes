# frozen_string_literal: true

class DevSessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path
  before_action :require_non_production_environment, only: :create

  def create
    user = User.find(params[:id])
    start_new_session_for(user)
    kitchen = ActsAsTenant.without_tenant { user.kitchens.first }
    return redirect_to root_path unless kitchen

    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  def destroy
    terminate_session
    redirect_to root_path
  end

  private

  def require_non_production_environment
    head :not_found unless Rails.env.development? || Rails.env.test?
  end
end
