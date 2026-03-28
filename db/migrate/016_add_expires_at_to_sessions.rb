# frozen_string_literal: true

class AddExpiresAtToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :expires_at, :datetime
    # Existing sessions with NULL expires_at are excluded by Session.active scope,
    # effectively expiring them on deploy. Users simply re-authenticate.
  end
end
