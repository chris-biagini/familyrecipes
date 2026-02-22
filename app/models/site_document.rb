# frozen_string_literal: true

class SiteDocument < ApplicationRecord
  acts_as_tenant :kitchen

  validates :name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :content, presence: true
end
