# frozen_string_literal: true

class DevSessionsController < ApplicationController
  def create
    user = User.find(params[:id])
    session[:user_id] = user.id
    redirect_to kitchen_root_path(kitchen_slug: user.kitchens.first.slug)
  end

  def destroy
    reset_session
    redirect_to root_path
  end
end
