# AI Import Prompt Evaluation

Tooling for iterating on the Haiku system prompt used by `AiImportService`.

## Quick Start

```bash
ANTHROPIC_API_KEY=sk-... ruby test/ai_import/runner.rb
```

Runs all 10 test corpus recipes through the current `prompt_template.md`
and writes results to `test/ai_import/results/iteration_NNN/`.

## Directory Layout

```
test/ai_import/
  corpus/             10 test recipes (input.txt + expected.md pairs)
  prompt_template.md  The Haiku system prompt being iterated on
  runner.rb           Evaluation orchestrator
  scorers/            Scoring modules (parse, format, fidelity judge)
  results/            Per-iteration outputs and scores
```

## Scoring Pipeline

1. **Layer 1 — Parse Check** (pass/fail): Feeds output through
   `LineClassifier` → `RecipeBuilder`. Checks for valid title, step
   structure, and minimum ingredient count.

2. **Layer 2 — Format Check** (percentage): Algorithmic checks for
   ASCII fractions, prep note formatting, valid categories, detritus
   patterns, step header format, ingredient name length, etc.

3. **Layer 3 — Fidelity Judge** (Sonnet): Compares original input
   vs. Haiku output vs. gold standard. Returns structured JSON with
   missing/added ingredients, changed quantities, and fidelity/detritus
   scores (0-100 each).

**Aggregate formula:**
`parse_pass ? (0.3 * format% + 0.4 * fidelity + 0.3 * detritus) : 0`

## Ralph Loop

The evaluation tooling is designed to be driven by a ralph loop agent:

1. Agent runs `runner.rb` → reads `summary.md`
2. Identifies failure patterns in lowest-scoring recipes
3. Edits `prompt_template.md` to address failures
4. Runs `runner.rb` again → compares scores
5. Repeats until convergence (overall > 85, worst > 70) or 8 iterations

## Corpus

Test recipes are static synthetic inputs spanning 4 types:

- **Blog posts** (recipes 1-3): varying blog noise levels
- **Recipe card widgets** (recipes 4-6): varying widget complexity
- **OCR/cookbook scans** (recipes 7-8): varying scan quality
- **Clean handwritten** (recipes 9-10): varying formality

Each recipe has a hand-written `expected.md` gold standard.

## Cost

~$0.10-0.20 per iteration (10 Haiku + 10 Sonnet calls). A full
8-iteration loop runs under $2 total.
