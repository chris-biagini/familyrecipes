# frozen_string_literal: true

class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :kitchens, through: :memberships

  validates :name, presence: true
  validates :email, uniqueness: true, allow_nil: true
end
