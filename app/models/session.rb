# frozen_string_literal: true

# Database-backed browser session. Created by the Authentication concern when
# a user logs in (via trusted headers or dev login), stored as a signed cookie.
# ActionCable connections also authenticate through the session cookie.
class Session < ApplicationRecord
  belongs_to :user

  scope :active, -> { where('expires_at > ?', Time.current) }

  before_create :set_default_expiry

  def self.cleanup_stale
    where(expires_at: ..Time.current).delete_all
  end

  private

  def set_default_expiry
    self.expires_at ||= 30.days.from_now
  end
end
