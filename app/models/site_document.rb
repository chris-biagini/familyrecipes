# frozen_string_literal: true

class SiteDocument < ApplicationRecord
  belongs_to :kitchen

  validates :name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :content, presence: true
end
