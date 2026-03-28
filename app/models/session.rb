# frozen_string_literal: true

# Database-backed browser session. Created by the Authentication concern when
# a user logs in (via trusted headers or dev login), stored as a signed cookie.
# ActionCable connections also authenticate through the session cookie.
class Session < ApplicationRecord
  belongs_to :user
end
