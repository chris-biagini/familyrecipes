# frozen_string_literal: true

class SiteDocument < ApplicationRecord
  acts_as_tenant :kitchen

  validates :name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :content, presence: true

  def self.content_for(name, fallback_path: nil)
    find_by(name: name)&.content || read_fallback(fallback_path)
  end

  def self.read_fallback(path)
    File.read(path) if path && File.exist?(path)
  end
  private_class_method :read_fallback
end
