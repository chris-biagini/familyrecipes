# frozen_string_literal: true

# Doc-vs-app contract verification. Parses help docs and checks that
# referenced app sections and settings actually exist in the app. Run via:
#   ruby -Itest test/release/doc_contract_check.rb
#
# NOT named _test.rb to avoid inclusion in the normal test suite.
#
# Key collaborators: ActionDispatch::IntegrationTest, Kitchen model,
# docs/help/ markdown files.

require_relative '../test_helper'

class DocContractCheck < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
  end

  test 'app sections referenced in help docs respond successfully' do
    routes = extract_app_route_references
    failures = []

    routes.each do |route_info|
      path = route_info[:path]
      begin
        get path
        unless response.status.in?([200, 301, 302])
          failures << "#{route_info[:source]}: #{path} returned #{response.status}"
        end
      rescue ActionController::RoutingError
        failures << "#{route_info[:source]}: #{path} — no matching route"
      end
    end

    assert_empty failures, "Doc contract violations:\n#{failures.join("\n")}"
  end

  test 'settings mentioned in docs correspond to Kitchen columns or known env vars' do
    column_refs, env_var_refs = extract_setting_references
    kitchen_columns = Kitchen.column_names.to_set

    missing_columns = column_refs.reject { |s| kitchen_columns.include?(s[:identifier]) }
    unknown_env_vars = env_var_refs.reject { |s| known_env_var_settings.include?(s[:identifier]) }
    failures = missing_columns + unknown_env_vars

    assert_empty failures,
                 "Settings in docs not found in Kitchen model or known env vars:\n#{failures.map do |s|
                   "  #{s[:source]}: #{s[:identifier]}"
                 end.join("\n")}"
  end

  private

  def help_docs_path
    Rails.root.join('docs/help')
  end

  def help_doc_files
    Dir[help_docs_path.join('**/*.md')].reject { |f| f.include?('.jekyll-cache') }
  end

  # Extracts app section references from Jekyll baseurl links in docs.
  # Maps top-level doc sections to their corresponding app routes.
  # Sections with no app-level route (import-export) are skipped.
  def extract_app_route_references
    # Recipes live on the homepage (kitchen_root), not a /recipes index route
    section_to_app_route = {
      'recipes' => kitchen_root_path(kitchen_slug:),
      'groceries' => groceries_path(kitchen_slug:),
      'menu' => menu_path(kitchen_slug:),
      'ingredients' => ingredients_path(kitchen_slug:),
      'settings' => settings_path(kitchen_slug:)
    }

    seen_sections = Set.new
    routes = []

    help_doc_files.each do |file|
      relative = Pathname.new(file).relative_path_from(help_docs_path).to_s
      content = File.read(file)

      # Match {{ site.baseurl }}/section/... and prev:/next: front matter paths
      content.scan(%r{(?:site\.baseurl\}\}/|prev:|next:)\s*(/[a-z][a-z0-9_/-]*)}) do |match|
        top_level_section = match[0].split('/').find(&:present?)
        next unless top_level_section
        next if seen_sections.include?(top_level_section)
        next unless section_to_app_route.key?(top_level_section)

        seen_sections.add(top_level_section)
        routes << { path: section_to_app_route[top_level_section], source: relative }
      end
    end

    routes
  end

  # Returns [column_refs, env_var_refs] — two arrays of {identifier:, source:} hashes.
  # Column refs map to Kitchen columns; env var refs map to deployment-level env vars.
  def extract_setting_references
    column_map = {
      'show nutrition' => 'show_nutrition',
      'display nutrition' => 'show_nutrition',
      'decorate' => 'decorate_tags',
      'site title' => 'site_title',
      'homepage heading' => 'homepage_heading',
      'homepage subtitle' => 'homepage_subtitle'
    }

    env_var_map = {
      'usda api key' => 'USDA_API_KEY',
      'anthropic api key' => 'ANTHROPIC_API_KEY'
    }

    column_refs = []
    env_var_refs = []

    help_doc_files.each do |file|
      relative = Pathname.new(file).relative_path_from(help_docs_path).to_s
      content = File.read(file)

      column_map.each do |phrase, column|
        column_refs << { identifier: column, source: relative } if content.downcase.include?(phrase)
      end

      env_var_map.each do |phrase, var|
        env_var_refs << { identifier: var, source: relative } if content.downcase.include?(phrase)
      end
    end

    [column_refs.uniq { |s| s[:identifier] }, env_var_refs.uniq { |s| s[:identifier] }]
  end

  def known_env_var_settings
    %w[USDA_API_KEY ANTHROPIC_API_KEY].to_set
  end
end
