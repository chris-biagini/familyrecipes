# frozen_string_literal: true

module ApplicationCable
  # Authenticates WebSocket connections via the same signed session cookie used
  # by HTTP requests. Rejects connections without a valid session — ActionCable
  # is member-only, unlike the public HTTP read paths.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      session = Session.find_by(id: cookies.signed[:session_id])
      session&.user || reject_unauthorized_connection
    end
  end
end
