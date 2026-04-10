# Magic Phrases Word List Redesign

**Date:** 2026-04-09
**Branch:** feature/auth
**Status:** Approved

## Problem

The join code word lists produce phrases that don't read like plausible
restaurant dishes. Column 1 ("techniques") contains imperative cooking verbs
("proof", "dice", "julienne") rather than menu-style adjectives ("braised",
"crispy", "smoked"). The ingredient list is modest at 250 words. Some words
across all lists fail the phone test — hard to pronounce or spell for English
speakers.

## Goals

- Phrases should read like a dish on a restaurant menu:
  `braised cauliflower tempeh ragout`
- All words must be phone-friendly — pronounceable and spellable by an English
  speaker without clarification
- Single words only, lowercase ASCII only
- Improve entropy as a pleasant side effect of better, bigger lists — not as a
  hard target
- Keep the 4-word format: `[descriptor] [ingredient] [ingredient] [dish]`

## Non-Goals

- Hitting a specific entropy bit count
- Changing the security model (hashing, expiration, single-use)
- Adding a 5th word slot
- Blocklisting unfortunate combinations
- Categorizing or weighting words within lists

## Design

### Column 1: Descriptors (renamed from "techniques")

Replace all 98 current cooking verbs with a new list mixing:

- **Cooking-method adjectives** — past-tense or adjective form: *braised,
  roasted, smoked, crispy, seared, charred, poached, whipped, pickled,
  grilled, toasted, steamed, cured, glazed, blistered, caramelized...*
- **Vibe/style words** — restaurant/cookbook aesthetic: *rustic, golden,
  harvest, farmhouse, garden...*

Target: ~120-150 words. YAML key changes from `techniques` to `descriptors`.

### Column 2-3: Ingredients

Expand from 250 to ~500 words. Apply the phone-friendly filter to the
existing list (remove words like *achiote, adzuki, galangal, freekeh,
fenugreek, jicama, zaatar, jute, shiso, tobiko, kohlrabi, kumquat*). Keep
loanwords that have crossed into common English (*tofu, wasabi, sesame,
mango, quinoa*). Grow by adding everyday ingredients across categories:
fruits, vegetables, proteins, grains, dairy, herbs/spices, pantry staples.

Two ingredient slots draw from the same pool; existing no-repeat logic
preserved.

### Column 4: Dishes

Apply the phone-friendly filter (remove *okonomiyaki, nigirizushi,
zabaglione, uramaki, fattoush, escabeche, pastilla, kedgeree* etc.). Keep
established loanwords (*risotto, ramen, taco, burrito, lasagna, hummus*).
Grow with English/comfort food territory: *chili, stew, hash, skillet,
medley, potpie, flatbread, bake, bowl* etc.

Target: ~120-150 words, grow modestly if quality holds.

### Entropy

With rough targets of 135 x 500 x 499 x 130 = ~4.4 billion combinations
= ~32 bits of entropy. Comfortably above typical human-chosen passwords
with complexity rules (~30 bits). More than sufficient given rate limiting
(10 attempts/hour).

### Code Changes

- **YAML:** `db/seeds/resources/join-code-words.yaml` — replace all three
  lists, rename `techniques` key to `descriptors`
- **Generator:** `lib/join_code_generator.rb` — rename `techniques` attribute
  to `descriptors`, update `generate` method variable name
- **Initializer:** no changes needed (calls `load!` which reads YAML keys)
- **Tests:** `test/models/join_code_generator_test.rb` — rename technique
  references to descriptor, update minimum thresholds:
  - descriptors >= 100 (was techniques >= 60)
  - ingredients >= 400 (was >= 200)
  - dishes >= 100 (was >= 80)

### What Doesn't Change

- Generator logic (pick 4 words, ensure two ingredients differ)
- YAML file location
- Kitchen model integration (column name, encryption, lookup)
- Rate limiting, normalization
- No blocklist, no weighting, no sub-categories

## Word Curation Process

Use parallel agents to brainstorm candidate words for each column. Apply the
phone-friendly filter: if you'd hesitate saying it to a stranger on the
phone, it's out. Prefer fun and evocative words over bland ones. The final
lists are curated by reviewing agent output for quality dropoff.
