# frozen_string_literal: true

# Abstract base for WebSocket channels. Turbo::StreamsChannel (from turbo-rails)
# is the primary channel; page-refresh broadcasts and targeted morphs flow through it.
module ApplicationCable
  class Channel < ActionCable::Channel::Base
  end
end
