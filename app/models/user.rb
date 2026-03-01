# frozen_string_literal: true

# A person who can log in and be a member of one or more Kitchens. Created
# via trusted-header auth (Authelia in production) or DevSessionsController
# in dev/test. Has no password — authentication is external. The session layer
# (Session model + Authentication concern) is auth-agnostic so new "front doors"
# can be added without touching User.
class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :kitchens, through: :memberships
  has_many :sessions, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
end
