# frozen_string_literal: true

class DevSessionsController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def create
    user = User.find(params[:id])
    session[:user_id] = user.id
    kitchen = ActsAsTenant.without_tenant { user.kitchens.first }
    redirect_to kitchen_root_path(kitchen_slug: kitchen.slug)
  end

  def destroy
    reset_session
    redirect_to root_path
  end
end
