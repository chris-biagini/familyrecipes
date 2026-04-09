# frozen_string_literal: true

# Join table linking Users to Kitchens. Presence of a Membership record is the
# authorization gate for write operations and member-only pages (menu, groceries,
# ingredients). Members join via the /join flow with a kitchen's join code.
class Membership < ApplicationRecord
  acts_as_tenant :kitchen
  belongs_to :user

  validates :user_id, uniqueness: { scope: :kitchen_id }
end
