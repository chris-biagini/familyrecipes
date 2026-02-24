# frozen_string_literal: true

class Kitchen < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  has_many :categories, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :ingredient_catalog, dependent: :destroy, class_name: 'IngredientCatalog'
  has_one :grocery_list, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  def member?(user)
    return false unless user

    memberships.exists?(user: user)
  end
end
