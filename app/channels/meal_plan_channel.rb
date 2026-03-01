# frozen_string_literal: true

class MealPlanChannel < ApplicationCable::Channel
  def subscribed
    kitchen = Kitchen.find_by(slug: params[:kitchen_slug])
    return reject unless authorized?(kitchen)

    stream_for kitchen
    ActsAsTenant.with_tenant(kitchen) do
      self.class.broadcast_version(kitchen, MealPlan.for_kitchen(kitchen).lock_version)
    end
  end

  def self.broadcast_version(kitchen, version)
    broadcast_to(kitchen, version: version)
  end

  def self.broadcast_content_changed(kitchen)
    broadcast_to(kitchen, type: 'content_changed')
  end

  private

  def authorized?(kitchen)
    return false unless kitchen

    ActsAsTenant.with_tenant(kitchen) { kitchen.member?(current_user) }
  end
end
