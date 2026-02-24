# frozen_string_literal: true

class GroceryListChannel < ApplicationCable::Channel
  def subscribed
    kitchen = Kitchen.find_by(slug: params[:kitchen_slug])
    reject unless kitchen

    stream_for kitchen
  end

  def self.broadcast_version(kitchen, version)
    broadcast_to(kitchen, version: version)
  end

  def self.broadcast_content_changed(kitchen)
    broadcast_to(kitchen, type: 'content_changed')
  end
end
