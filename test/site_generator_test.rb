require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'

class SiteGeneratorTest < Minitest::Test
  def test_generate_completes_without_error
    project_root = File.expand_path('..', __dir__)
    generator = FamilyRecipes::SiteGenerator.new(project_root)
    generator.generate
  end

  def test_generate_produces_expected_output_files
    project_root = File.expand_path('..', __dir__)
    output_dir = File.join(project_root, 'output', 'web')

    FamilyRecipes::SiteGenerator.new(project_root).generate

    assert File.exist?(File.join(output_dir, 'index.html')), 'homepage should exist'
    assert File.exist?(File.join(output_dir, 'index', 'index.html')), 'ingredient index should exist'
    assert File.exist?(File.join(output_dir, 'groceries', 'index.html')), 'groceries page should exist'
    assert File.exist?(File.join(output_dir, 'style.css')), 'stylesheet should exist'
    assert File.exist?(File.join(output_dir, 'groceries.css')), 'groceries CSS should exist'
    assert File.exist?(File.join(output_dir, 'groceries.js')), 'groceries JS should exist'
    assert File.exist?(File.join(output_dir, 'qrcodegen.js')), 'QR code library should exist'
    assert File.exist?(File.join(output_dir, 'manifest.json')), 'PWA manifest should exist'
    assert File.exist?(File.join(output_dir, 'sw.js')), 'service worker should exist'

    # Should have at least one recipe HTML + TXT pair
    html_files = Dir.glob(File.join(output_dir, '*.html')).reject { |f| f.end_with?('index.html', '404.html') }
    txt_files = Dir.glob(File.join(output_dir, '*.txt'))
    assert html_files.size > 0, 'should generate recipe HTML files'
    assert txt_files.size > 0, 'should generate recipe TXT files'
  end
end
