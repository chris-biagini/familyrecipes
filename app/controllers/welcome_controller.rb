# frozen_string_literal: true

# One-time welcome screen shown after a new member joins a kitchen. Displays
# the kitchen name and join code with a prompt to save it. The kitchen ID is
# passed as a signed, time-limited parameter to prevent bookmarking as a
# way to peek at join codes.
#
# - JoinsController: redirects here after new member registration
# - Kitchen: join_code display
class WelcomeController < ApplicationController
  skip_before_action :set_kitchen_from_path

  layout 'auth'

  def show
    kitchen = resolve_signed_kitchen
    return redirect_to root_path unless kitchen

    @kitchen_name = kitchen.name
    @join_code = kitchen.join_code
    @kitchen_slug = kitchen.slug
  end

  private

  def resolve_signed_kitchen
    kitchen_id = Rails.application.message_verifier(:welcome).verified(params[:k], purpose: :welcome)
    return nil unless kitchen_id

    ActsAsTenant.without_tenant { Kitchen.find_by(id: kitchen_id) }
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
