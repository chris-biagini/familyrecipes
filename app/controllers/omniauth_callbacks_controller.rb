# frozen_string_literal: true

class OmniauthCallbacksController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def create
    auth = request.env['omniauth.auth']
    return redirect_to root_path, alert: 'Authentication failed' unless auth

    user = find_or_create_user(auth)
    start_new_session_for(user)
    redirect_to after_authentication_url
  end

  def destroy
    terminate_session
    redirect_to root_path
  end

  def failure
    redirect_to root_path, alert: 'Authentication failed. Please try again.'
  end

  private

  def find_or_create_user(auth)
    service = ConnectedService.find_by(provider: auth.provider, uid: auth.uid)
    return service.user if service

    user = User.find_by(email: auth.info.email) || User.create!(
      name: auth.info.name,
      email: auth.info.email
    )
    user.connected_services.find_or_create_by!(provider: auth.provider, uid: auth.uid)
    user
  end
end
