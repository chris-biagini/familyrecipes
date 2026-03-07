# frozen_string_literal: true

require 'test_helper'

class ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    setup_test_category
  end

  test 'create requires membership' do
    post import_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'create with no files returns JSON message' do
    log_in
    post import_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_match(/no importable files/i, parsed_message)
  end

  test 'imports a recipe file via POST' do
    log_in
    file = uploaded_recipe_file('Bagels.md', "# Bagels\n\n## Boil\n\n- Flour, 3 cups\n\nBoil them.")
    post import_path(kitchen_slug: kitchen_slug), params: { files: [file] }

    assert_response :success
    assert_match(/1 recipe/, parsed_message)
    assert @kitchen.recipes.find_by(slug: 'bagels')
  end

  test 'imports a ZIP file via POST' do
    log_in
    zip_data = build_zip('Bread/Focaccia.md' => "# Focaccia\n\n## Mix\n\n- Flour, 3 cups\n\nMix.")
    file = Rack::Test::UploadedFile.new(
      StringIO.new(zip_data), 'application/zip', original_filename: 'export.zip'
    )
    post import_path(kitchen_slug: kitchen_slug), params: { files: [file] }

    assert_response :success
    assert @kitchen.recipes.find_by(slug: 'focaccia')
  end

  test 'JSON summarizes multiple data types' do
    log_in
    yaml = { 'Test Ingredient' => { 'aisle' => 'Pantry' } }.to_yaml
    zip_data = build_zip(
      'Bread/Focaccia.md' => "# Focaccia\n\n## Mix\n\n- Flour, 3 cups\n\nMix.",
      'quick-bites.txt' => "Chips\nSalsa",
      'custom-ingredients.yaml' => yaml
    )
    file = Rack::Test::UploadedFile.new(
      StringIO.new(zip_data), 'application/zip', original_filename: 'export.zip'
    )
    post import_path(kitchen_slug: kitchen_slug), params: { files: [file] }

    assert_response :success
    assert_match(/1 recipe/, parsed_message)
    assert_match(/1 ingredient/, parsed_message)
    assert_match(/Quick Bites/, parsed_message)
  end

  private

  def parsed_message
    response.parsed_body['message']
  end

  def uploaded_recipe_file(filename, content)
    Rack::Test::UploadedFile.new(
      StringIO.new(content), 'text/plain', original_filename: filename
    )
  end

  def build_zip(entries = {})
    buffer = Zip::OutputStream.write_buffer do |zos|
      entries.each do |name, content|
        zos.put_next_entry(name)
        zos.write(content)
      end
    end
    buffer.string
  end
end
