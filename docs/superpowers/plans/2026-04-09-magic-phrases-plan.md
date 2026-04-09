# Magic Phrases Word List Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign join code word lists so generated phrases read like restaurant menu items, and improve entropy through larger, better-curated lists.

**Architecture:** Data-only change to `join-code-words.yaml` plus a mechanical rename of `techniques` to `descriptors` in the generator module and tests. Word curation uses parallel agents to brainstorm candidates, with manual quality review. No changes to generator logic, kitchen model, or security model.

**Tech Stack:** Ruby, YAML, Minitest

**Spec:** `docs/superpowers/specs/2026-04-09-magic-phrases-design.md`

---

### Task 1: Rename techniques to descriptors

Mechanical rename across three files. Keeps existing word list temporarily so tests continue passing throughout.

**Files:**
- Modify: `db/seeds/resources/join-code-words.yaml:1-2` (YAML key)
- Modify: `lib/join_code_generator.rb:4,14,17-18,24` (module attribute + header)
- Modify: `test/models/join_code_generator_test.rb:7,13,19,27,39,43` (all technique refs)

- [ ] **Step 1: Update the test file — rename all `techniques` references to `descriptors`**

Replace every occurrence of `techniques` with `descriptors` in the test file:

```ruby
# frozen_string_literal: true

require 'test_helper'

class JoinCodeGeneratorTest < ActiveSupport::TestCase
  test 'word lists are loaded and frozen' do
    assert_predicate JoinCodeGenerator.descriptors, :frozen?
    assert_predicate JoinCodeGenerator.ingredients, :frozen?
    assert_predicate JoinCodeGenerator.dishes, :frozen?
  end

  test 'word lists are non-empty' do
    assert_operator JoinCodeGenerator.descriptors.size, :>=, 60
    assert_operator JoinCodeGenerator.ingredients.size, :>=, 200
    assert_operator JoinCodeGenerator.dishes.size, :>=, 80
  end

  test 'all words are lowercase ASCII' do
    all_words = JoinCodeGenerator.descriptors + JoinCodeGenerator.ingredients + JoinCodeGenerator.dishes

    all_words.each do |word|
      assert_match(/\A[a-z]+\z/, word, "Word '#{word}' contains non-ASCII or non-lowercase characters")
    end
  end

  test 'no duplicate words within or across lists' do
    all_words = JoinCodeGenerator.descriptors + JoinCodeGenerator.ingredients + JoinCodeGenerator.dishes

    assert_equal all_words.size, all_words.uniq.size, 'Duplicate words found in word lists'
  end

  test 'generate produces 4-word string' do
    code = JoinCodeGenerator.generate
    words = code.split

    assert_equal 4, words.size
  end

  test 'generate follows descriptor-ingredient-ingredient-dish format' do
    code = JoinCodeGenerator.generate
    words = code.split

    assert_includes JoinCodeGenerator.descriptors, words[0]
    assert_includes JoinCodeGenerator.ingredients, words[1]
    assert_includes JoinCodeGenerator.ingredients, words[2]
    assert_includes JoinCodeGenerator.dishes, words[3]
  end

  test 'two ingredients are different' do
    20.times do
      code = JoinCodeGenerator.generate
      words = code.split

      assert_not_equal words[1], words[2], "Duplicate ingredients in: #{code}"
    end
  end

  test 'generate produces different codes' do
    codes = Array.new(10) { JoinCodeGenerator.generate }

    assert_operator codes.uniq.size, :>, 1, 'All generated codes were identical'
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `ruby -Itest test/models/join_code_generator_test.rb`
Expected: FAIL — `JoinCodeGenerator` still exposes `techniques`, not `descriptors`.

- [ ] **Step 3: Update the generator module**

Replace the full file `lib/join_code_generator.rb`:

```ruby
# frozen_string_literal: true

# Generates cooking-themed join codes in the format:
# "descriptor ingredient ingredient dish"
# Loaded once at boot via initializer; arrays frozen for thread safety.
# Uses SecureRandom for index selection.
#
# - Kitchen: calls generate on create, stores result in join_code column
# - config/initializers/join_code_generator.rb: triggers load! at boot
module JoinCodeGenerator
  WORDS_PATH = Rails.root.join('db/seeds/resources/join-code-words.yaml')

  class << self
    attr_reader :descriptors, :ingredients, :dishes

    def load!
      data = YAML.load_file(WORDS_PATH)
      @descriptors = data.fetch('descriptors').map(&:freeze).freeze
      @ingredients = data.fetch('ingredients').map(&:freeze).freeze
      @dishes = data.fetch('dishes').map(&:freeze).freeze
    end

    def generate
      d = descriptors[SecureRandom.random_number(descriptors.size)]
      i1 = ingredients[SecureRandom.random_number(ingredients.size)]
      i2 = pick_second_ingredient(i1)
      dish = dishes[SecureRandom.random_number(dishes.size)]
      "#{d} #{i1} #{i2} #{dish}"
    end

    private

    def pick_second_ingredient(first)
      loop do
        candidate = ingredients[SecureRandom.random_number(ingredients.size)]
        return candidate unless candidate == first
      end
    end
  end
end
```

- [ ] **Step 4: Rename the YAML key**

In `db/seeds/resources/join-code-words.yaml`, change the first key from `techniques:` to `descriptors:`. Keep all existing words for now.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `ruby -Itest test/models/join_code_generator_test.rb`
Expected: all 8 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/join_code_generator.rb test/models/join_code_generator_test.rb db/seeds/resources/join-code-words.yaml
git commit -m "Rename techniques to descriptors in join code generator"
```

---

### Task 2: Curate descriptor word list

Replace the 98 cooking verbs with ~120-150 menu-style words mixing cooking-method adjectives and vibe/style words.

**Files:**
- Modify: `db/seeds/resources/join-code-words.yaml` (descriptors section)

- [ ] **Step 1: Brainstorm descriptor candidates using parallel agents**

Spawn three parallel agents to generate candidate words:

**Agent A — Cooking-method adjectives:** Generate ~100 words that describe how a dish was prepared, in adjective/past-tense form. Examples: *braised, roasted, smoked, crispy, seared, charred, poached, whipped, pickled, grilled, toasted, steamed, cured, glazed, blistered, caramelized, simmered, peppered, buttered, stuffed, crusted, candied, drizzled, infused, marinated, blackened, broiled, chilled, folded, herbed, iced, layered, melted, minted, peppered, reduced, salted, savory, spiced, sugared, tossed, wilted.* Must be single words, lowercase ASCII, phone-friendly (easy to pronounce/spell over the phone).

**Agent B — Vibe/style words:** Generate ~80 words that evoke a restaurant or cookbook aesthetic. Examples: *rustic, golden, harvest, farmhouse, garden, classic, hearty, tender, velvet, autumn, spring, summer, winter, morning, sunset, vintage, cottage, country, fresh, sunny, bright, savory, sweet, tangy, smoky, homestyle, festive, cozy, woodland, lakeside, prairie.* Must pass the "first word on a restaurant menu" test. Single words, lowercase ASCII, phone-friendly.

**Agent C — Crosscheck:** Review outputs of A and B for duplicates, words that overlap with the existing ingredient or dish lists, and words that fail the phone test. Flag any that sound weird as the first word of a dish name.

- [ ] **Step 2: Curate the final list**

Review agent output. Apply these filters:
- Would this word plausibly appear first on a restaurant menu item?
- Can you say it over the phone without spelling it?
- Is it a single lowercase ASCII word?
- Does it NOT appear in the ingredients or dishes lists?

Target: 120-150 words, alphabetically sorted.

- [ ] **Step 3: Replace the descriptors section in the YAML**

Replace everything under the `descriptors:` key in `join-code-words.yaml` with the curated list. Each word on its own `  - word` line, alphabetically sorted.

- [ ] **Step 4: Run the tests**

Run: `ruby -Itest test/models/join_code_generator_test.rb`
Expected: all 8 tests PASS (minimum threshold is still 60; new list will exceed that).

- [ ] **Step 5: Spot-check generated codes**

Run in Rails console:
```bash
bin/rails runner "JoinCodeGenerator.load!; 20.times { puts JoinCodeGenerator.generate }"
```
Eyeball the output. Every code should read like a plausible restaurant dish.

- [ ] **Step 6: Commit**

```bash
git add db/seeds/resources/join-code-words.yaml
git commit -m "Replace technique verbs with menu-style descriptors"
```

---

### Task 3: Curate ingredient word list

Filter the existing 250 ingredients for phone-friendliness, then expand to ~500 total.

**Files:**
- Modify: `db/seeds/resources/join-code-words.yaml` (ingredients section)

- [ ] **Step 1: Filter existing ingredients**

Review the current 250 ingredients. Remove words that fail the phone test — hard to pronounce or spell for English speakers. Known removals from the spec: *achiote, adzuki, galangal, freekeh, fenugreek, jicama, zaatar, jute, shiso, tobiko, kohlrabi, kumquat, broccolini, cobnut, udon, vermicelli, edamame, daikon, tomatillo.* Also review for other borderline words (e.g., *chervil, sorrel, sumac, maitake, lychee, yuzu*).

Keep loanwords that have entered common English: *tofu, wasabi, sesame, mango, quinoa, basil, cilantro, jalapeno, parmesan, prosciutto, mozzarella.*

- [ ] **Step 2: Brainstorm new ingredients using parallel agents**

Spawn agents to generate candidates across categories:

**Agent A — Fruits and Vegetables:** Generate ~100 additional everyday fruits and vegetables not already in the list. Examples: *kiwi, grape, tangerine, broccoli, zucchini* (already present — avoid dupes). Think: what is in the produce section of a regular grocery store?

**Agent B — Proteins and Dairy:** Generate ~80 additional proteins (meats, fish, legumes) and dairy items. Examples: *chicken, turkey, beef, bison, catfish, grouper, haddock, mahi* (already present — avoid dupes). Think: what is on a diner menu?

**Agent C — Grains, Herbs, Spices, Pantry:** Generate ~80 additional grains, herbs, spices, and pantry staples. Examples: *bread, flour, pasta* (check for overlap with dishes list). Think: what is in a well-stocked home kitchen?

**Agent D — Crosscheck:** Deduplicate across all agent outputs and the existing filtered list. Flag any words that overlap with the descriptors or dishes lists. Flag phone-unfriendly words.

- [ ] **Step 3: Curate the final list**

Review agent output. Apply filters:
- Can you say it over the phone without spelling it?
- Single lowercase ASCII word?
- Not a duplicate of any word in descriptors or dishes?
- Is it recognizably a food ingredient to most English speakers?

Target: ~500 words. If quality drops off before 500, stop at whatever count keeps the list strong. Alphabetically sorted.

- [ ] **Step 4: Replace the ingredients section in the YAML**

Replace everything under the `ingredients:` key in `join-code-words.yaml` with the curated list.

- [ ] **Step 5: Run the tests**

Run: `ruby -Itest test/models/join_code_generator_test.rb`
Expected: all 8 tests PASS.

- [ ] **Step 6: Spot-check generated codes**

Run in Rails console:
```bash
bin/rails runner "JoinCodeGenerator.load!; 20.times { puts JoinCodeGenerator.generate }"
```
Eyeball the output for any weird ingredient pairings or unrecognizable words.

- [ ] **Step 7: Commit**

```bash
git add db/seeds/resources/join-code-words.yaml
git commit -m "Expand ingredients to ~500 phone-friendly words"
```

---

### Task 4: Curate dish word list

Filter the existing 121 dishes for phone-friendliness and expand where quality holds.

**Files:**
- Modify: `db/seeds/resources/join-code-words.yaml` (dishes section)

- [ ] **Step 1: Filter existing dishes**

Remove words that fail the phone test. Known removals from the spec: *okonomiyaki, nigirizushi, zabaglione, uramaki, fattoush, escabeche, pastilla, kedgeree.* Also review: *bourguignon, cacciatore, puttanesca, cioppino, tabbouleh, cassoulet, arancini, moussaka, shakshuka.* Keep well-known loanwords: *risotto, ramen, taco, burrito, lasagna, hummus, pesto, sushi, falafel, gnocchi.*

- [ ] **Step 2: Brainstorm new dishes using parallel agents**

Spawn agents to generate candidates:

**Agent A — English/comfort food:** Generate ~60 dish names from English-speaking cuisine. Examples: *chili, stew, hash, skillet, medley, potpie, flatbread, bake, bowl, scramble, ragout, chutney, compote, tartare, fricassee* (check — some may already be present or overlap with descriptors). Think: American diner, British pub, brunch menu.

**Agent B — Well-known international dishes:** Generate ~40 internationally-known dish names that pass the phone test. Examples: *curry, tikka, kebab, gyro, pita, naan* (some already present). Think: dishes that appear on menus in any mid-size American city.

**Agent C — Crosscheck:** Deduplicate, flag overlaps with descriptors and ingredients lists, flag phone-unfriendly words.

- [ ] **Step 3: Curate the final list**

Review agent output. Apply filters:
- Does this word work as the last word of a dish name? ("braised salmon walnut ___")
- Can you say it over the phone without spelling it?
- Single lowercase ASCII word?
- Not a duplicate of any word in descriptors or ingredients?

Target: ~120-150 words. Alphabetically sorted.

- [ ] **Step 4: Replace the dishes section in the YAML**

Replace everything under the `dishes:` key in `join-code-words.yaml` with the curated list.

- [ ] **Step 5: Run the tests**

Run: `ruby -Itest test/models/join_code_generator_test.rb`
Expected: all 8 tests PASS.

- [ ] **Step 6: Spot-check generated codes**

Run in Rails console:
```bash
bin/rails runner "JoinCodeGenerator.load!; 20.times { puts JoinCodeGenerator.generate }"
```
Final eyeball check — every generated code should read like a plausible restaurant dish.

- [ ] **Step 7: Commit**

```bash
git add db/seeds/resources/join-code-words.yaml
git commit -m "Filter and expand dish list for phone-friendliness"
```

---

### Task 5: Update test thresholds and final verification

Raise the minimum-size assertions to match the new list sizes and run the full test suite.

**Files:**
- Modify: `test/models/join_code_generator_test.rb:13-15` (threshold assertions)

- [ ] **Step 1: Update the test thresholds**

In `test/models/join_code_generator_test.rb`, change the `'word lists are non-empty'` test:

```ruby
  test 'word lists are non-empty' do
    assert_operator JoinCodeGenerator.descriptors.size, :>=, 100
    assert_operator JoinCodeGenerator.ingredients.size, :>=, 400
    assert_operator JoinCodeGenerator.dishes.size, :>=, 100
  end
```

- [ ] **Step 2: Run the join code generator tests**

Run: `ruby -Itest test/models/join_code_generator_test.rb`
Expected: all 8 tests PASS.

- [ ] **Step 3: Run the full test suite**

Run: `rake test`
Expected: all tests PASS. If any kitchen/join-code related tests reference `techniques`, fix them.

- [ ] **Step 4: Run RuboCop**

Run: `bundle exec rubocop lib/join_code_generator.rb test/models/join_code_generator_test.rb`
Expected: 0 offenses.

- [ ] **Step 5: Log final entropy**

Run in Rails console:
```bash
bin/rails runner "JoinCodeGenerator.load!; d = JoinCodeGenerator.descriptors.size; i = JoinCodeGenerator.ingredients.size; di = JoinCodeGenerator.dishes.size; combos = d * i * (i - 1) * di; bits = Math.log2(combos); puts \"Descriptors: #{d}, Ingredients: #{i}, Dishes: #{di}\"; puts \"Combinations: #{combos.to_i}\"; puts \"Entropy: #{bits.round(1)} bits\""
```
Expected: ~32 bits of entropy (exact number depends on final list sizes).

- [ ] **Step 6: Commit**

```bash
git add test/models/join_code_generator_test.rb
git commit -m "Raise join code word list minimum thresholds"
```
