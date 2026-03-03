# frozen_string_literal: true

# Abstract base for WebSocket channels. Turbo::StreamsChannel (from turbo-rails)
# is the primary channel; MealPlanBroadcaster pushes morphs through it.
module ApplicationCable
  class Channel < ActionCable::Channel::Base
  end
end
