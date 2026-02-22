# frozen_string_literal: true

class SiteDocument < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :content, presence: true
end
