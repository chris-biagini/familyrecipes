# frozen_string_literal: true

# A person who can sign in and be a member of one or more Kitchens. Created
# via the join flow (JoinsController) or the kitchen creation flow
# (KitchensController). Authentication is email-verified: a User is
# considered authenticated once they've consumed a valid MagicLink proving
# control of their email address. The session layer (Session model +
# Authentication concern) is auth-agnostic so new "front doors" (passkeys,
# OAuth) can be added without touching this model.
class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :kitchens, through: :memberships
  has_many :sessions, dependent: :destroy
  has_many :magic_links, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  def email_verified? = email_verified_at.present?

  def verify_email!
    return if email_verified?

    update!(email_verified_at: Time.current)
  end
end
