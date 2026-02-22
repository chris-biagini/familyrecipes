# frozen_string_literal: true

class GroceriesController < ApplicationController
  def show
    @categories = Category.ordered.includes(recipes: { steps: :ingredients })
    @grocery_aisles = load_grocery_aisles
    @alias_map = FamilyRecipes.build_alias_map(@grocery_aisles)
    @omit_set = build_omit_set
    @recipe_map = build_recipe_map
    @unit_plurals = collect_unit_plurals
    @quick_bites_by_subsection = load_quick_bites_by_subsection
    @quick_bites_content = quick_bites_document&.content || ''
    @grocery_aisles_content = grocery_aisles_document&.content || ''
  end

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_entity if content.blank?

    doc = SiteDocument.find_or_initialize_by(name: 'quick_bites')
    doc.content = content
    doc.save!

    render json: { status: 'ok' }
  end

  def update_grocery_aisles
    content = params[:content].to_s
    errors = validate_grocery_aisles(content)
    return render json: { errors: }, status: :unprocessable_entity if errors.any?

    doc = SiteDocument.find_or_initialize_by(name: 'grocery_aisles')
    doc.content = content
    doc.save!

    render json: { status: 'ok' }
  end

  private

  def load_grocery_aisles
    doc = grocery_aisles_document
    return fallback_grocery_aisles unless doc

    FamilyRecipes.parse_grocery_aisles_markdown(doc.content)
  end

  def fallback_grocery_aisles
    yaml_path = Rails.root.join('resources/grocery-info.yaml')
    return {} unless File.exist?(yaml_path)

    FamilyRecipes.parse_grocery_info(yaml_path)
  end

  def build_omit_set
    omit_key = @grocery_aisles.keys.find { |k| k.downcase.tr('_', ' ') == 'omit from list' }
    return Set.new unless omit_key

    @grocery_aisles[omit_key].to_set { |item| item[:name].downcase }
  end

  def build_recipe_map
    Recipe.includes(:category).to_h do |r|
      parsed = FamilyRecipes::Recipe.new(
        markdown_source: r.markdown_source,
        id: r.slug,
        category: r.category.name
      )
      [r.slug, parsed]
    end
  end

  def collect_unit_plurals
    @recipe_map.values
               .flat_map { |r| r.all_ingredients_with_quantities(@alias_map, @recipe_map) }
               .flat_map { |_, amounts| amounts.compact.filter_map(&:unit) }
               .uniq
               .to_h { |u| [u, FamilyRecipes::Inflector.unit_display(u, 2)] }
  end

  def load_quick_bites_by_subsection
    doc = quick_bites_document
    return {} unless doc

    FamilyRecipes.parse_quick_bites_content(doc.content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end

  def quick_bites_document
    @quick_bites_document ||= SiteDocument.find_by(name: 'quick_bites')
  end

  def grocery_aisles_document
    @grocery_aisles_document ||= SiteDocument.find_by(name: 'grocery_aisles')
  end

  def validate_grocery_aisles(content)
    return ['Content cannot be blank.'] if content.blank?

    parsed = FamilyRecipes.parse_grocery_aisles_markdown(content)
    validations = {
      'Must have at least one aisle (## Aisle Name).' => parsed.empty?
    }

    validations.select { |_msg, failed| failed }.keys
  end
end
