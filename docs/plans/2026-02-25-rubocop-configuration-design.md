# RuboCop Configuration Design

Closes #96.

## Summary

Add `rubocop-rails` and `rubocop-performance` plugins, tighten metric thresholds to aspirational levels with targeted inline exclusions, and expand linting scope to cover `config/` and `db/` (except migrations). Single commit, big-bang approach.

## Plugins

### Adding

| Plugin | Gem | Why |
|--------|-----|-----|
| `rubocop-rails` | `rubocop-rails` | Rails-specific cops: safe migrations, proper ActiveRecord usage, consistent test assertions |
| `rubocop-performance` | `rubocop-performance` | Flags patterns with faster alternatives |

### Not adding

- `rubocop-capybara` — no system tests yet
- `rubocop-rake` — only 2 rake files, minimal value

## Cop Configuration

### Rails cops requiring special handling

**Disabled for specific files:**
- `Rails/Output` — excluded for `lib/familyrecipes/build_validator.rb` (intentional CLI `puts`)

**Inline disables (with TODO comments):**
- `Rails/OutputSafety` — 5 calls in `recipes_helper.rb`, already audited by `rake lint:html_safe`
- `Rails/SkipsModelValidations` — 3 intentional `update_column` calls in jobs/models

**Auto-fixed (~95 offenses):**
- `Rails/RefuteMethods` (59) — `refute_*` → `assert_not_*`
- `Rails/ResponseParsedBody` (22) — `JSON.parse(response.body)` → `response.parsed_body`
- `Rails/HttpStatusNameConsistency` (9) — `:unprocessable_entity` → `:unprocessable_content`
- `Rails/Blank` (3) — `.nil? || .empty?` → `.blank?`

**Manually fixed (~15 offenses):**
- `Rails/IndexWith` (3), `Rails/IndexBy` (1) — use `index_with`/`index_by`
- `Rails/WhereMissing` (1) — use `where.missing`
- `Rails/EnvLocal` (1) — use `Rails.env.local?`
- `Rails/FilePath` (1), `Rails/RootPublicPath` (1) — use `Rails.root.join`/`Rails.public_path`
- `Rails/RakeEnvironment` (1) — add `:environment` dependency
- `Rails/InverseOf` (1) — add `:inverse_of` option
- `Rails/UniqueValidationWithoutIndex` (1) — add unique DB index or disable if intentional
- `Rails/Pluck` (3) — use `pluck` in tests
- `Performance/RedundantBlockCall` (1) — use `yield`
- `Performance/RedundantEqualityComparisonBlock` (1) — use `all?(Ingredient)`

## Aspirational Metric Thresholds

| Cop | Was | Now | Default | Exclusions |
|-----|-----|-----|---------|------------|
| `Metrics/MethodLength` | 35 | **15** | 10 | 8 methods |
| `Metrics/AbcSize` | 40 | **25** | 17 | 5 methods |
| `Metrics/CyclomaticComplexity` | 15 | **10** | 7 | 3 methods |
| `Metrics/PerceivedComplexity` | 15 | **10** | 8 | 4 methods |
| `Metrics/ClassLength` | 275 | **125** | 100 | 4 classes |
| `Metrics/ModuleLength` | 120 | **100** | 100 | 0 |
| `Metrics/BlockLength` | 25 | **25** | 25 | 0 |

Methods exceeding thresholds get inline `# rubocop:disable` with `# TODO:` comments. The `bin/*` and `test/**/*` exclusions for method-level metrics stay.

### Repeat offenders (refactoring any one removes multiple exclusions)

1. `parse_serving_size` — `nutrition_entry_helpers.rb` (MethodLength 33, AbcSize 34, Cyclomatic 14, Perceived 13)
2. `to_grams` — `nutrition_calculator.rb` (MethodLength 17, AbcSize 22.3, Cyclomatic 12, Perceived 12)
3. `aggregate_amounts` — `ingredient_aggregator.rb` (MethodLength 13, AbcSize 22.8, Cyclomatic 11, Perceived 11)
4. `nutrition_columns` — `recipes_helper.rb` (MethodLength 12, AbcSize 20.4, Cyclomatic 10, Perceived 11)
5. `parse_footer` — `recipe_builder.rb` (MethodLength 17, AbcSize 21.5, Cyclomatic 9, Perceived 10)
6. `parse` — `ingredient_parser.rb` (MethodLength 27, AbcSize 22.1, Cyclomatic 9, Perceived 9)

## Scope Changes

### Expanded (now linted)
- `config/**/*` — initializers, routes, environments
- `db/**/*` — seeds, seed data helpers

### Still excluded
- `vendor/**/*`
- `db/migrate/**/*`
- `db/schema.rb`

## Workflow

Keep `rake lint` as report-only. Auto-correct is a manual step (`rubocop -a` or `rubocop -A`).

## Implementation Order

1. Add gems to Gemfile, `bundle install`
2. Rewrite `.rubocop.yml` with new plugins, thresholds, exclusions
3. Run `rubocop -a` for safe auto-corrections
4. Fix remaining offenses manually
5. Add inline disables for intentional violations
6. Handle new offenses from expanded scope
7. Run full test suite + `rake lint`
8. Single commit closing #96
