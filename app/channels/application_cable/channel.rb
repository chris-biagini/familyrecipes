# frozen_string_literal: true

# Abstract base for WebSocket channels. MealPlanChannel is the sole channel;
# see its header comment for the ActsAsTenant gotcha.
module ApplicationCable
  class Channel < ActionCable::Channel::Base
  end
end
