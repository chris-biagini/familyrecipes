# frozen_string_literal: true

class Membership < ApplicationRecord
  belongs_to :kitchen
  belongs_to :user

  validates :user_id, uniqueness: { scope: :kitchen_id }
end
