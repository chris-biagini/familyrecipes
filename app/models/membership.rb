# frozen_string_literal: true

# Join table linking Users to Kitchens. Presence of a Membership record is the
# authorization gate for write operations and member-only pages (menu, groceries,
# ingredients). When exactly one Kitchen exists, new users are auto-joined via
# ApplicationController#auto_join_sole_kitchen.
class Membership < ApplicationRecord
  acts_as_tenant :kitchen
  belongs_to :user

  validates :user_id, uniqueness: { scope: :kitchen_id }
end
