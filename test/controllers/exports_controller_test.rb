# frozen_string_literal: true

require 'test_helper'

class ExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  # --- Access control ---

  test 'show requires membership' do
    get export_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  # --- Download ---

  test 'downloads ZIP for logged-in members' do
    log_in
    get export_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_equal 'application/zip', response.content_type
    assert_match(/\.zip/, response.headers['Content-Disposition'])
    assert_match(/attachment/, response.headers['Content-Disposition'])
  end

  test 'ZIP contains recipe files' do
    markdown = "# Bagels\n\nCategory: Bread\n\n## Steps\n\n- Flour, 2 cups\n\nBoil then bake."
    MarkdownImporter.import(markdown, kitchen: @kitchen)
    log_in
    get export_path(kitchen_slug: kitchen_slug)

    entries = extract_zip_entries(response.body)

    assert(entries.any? { |name| name.include?('Bagels.md') })
  end

  private

  def extract_zip_entries(zip_data)
    names = []
    Zip::InputStream.open(StringIO.new(zip_data)) do |zis|
      while (entry = zis.get_next_entry)
        names << entry.name
      end
    end
    names
  end
end
