# frozen_string_literal: true

class Membership < ApplicationRecord
  acts_as_tenant :kitchen
  belongs_to :user

  validates :user_id, uniqueness: { scope: :kitchen_id }
end
