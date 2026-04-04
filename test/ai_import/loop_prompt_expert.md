# Expert Prompt Tuning — Ralph Loop

You are iteratively improving the expert AI import prompt. Each iteration:
analyze what went wrong, make targeted prompt edits, re-evaluate, check
convergence.

## Step 1: Read State

Read `test/ai_import/results/state.json`. Note:
- Current iteration count
- Best score and which iteration produced it
- Patience counter (stops at 2)
- Prompt line count trend — is the prompt growing or shrinking?

If state.json does not exist, this is the first iteration. Skip to Step 3.

## Step 2: Analyze Failures

Read the most recent `test/ai_import/results/iteration_*/summary.md`.

Focus on, in priority order:
1. **Step structure** — the weakest baseline dimension. Are phases well-chosen?
   Are interleaved operations disentangled? Are simple recipes getting
   unnecessary explicit steps?
2. **Style voice** — watch for over-correction (telegraphic robot prose) AND
   under-correction (chatty blog voice surviving). The target is terse but
   human.
3. **Footer discipline** — invented substitutions, tips, or imperial
   equivalents not in the source.
4. **Outcome fidelity** — dropped ingredients, changed quantities, lost
   technique unique to this recipe.

Also look for **prompt trimming opportunities**:
- Rules that have never been violated — Sonnet may follow the convention
  naturally. These are candidates for removal.
- Redundant rules that say the same thing in different places.
- Examples that could be shorter without losing clarity.

## Step 3: Edit the Prompt

Edit `lib/familyrecipes/ai_import_prompt_expert.md`. Rules:

**Prefer removing or simplifying rules over adding new ones.** A shorter
prompt burns fewer tokens and gives the model less to misinterpret. Every
line in the prompt should earn its place.

- Bundle multiple targeted fixes per iteration when they address different,
  non-overlapping issues.
- If this is the first iteration, just verify the prompt looks correct and
  make no edits.
- Never rewrite the prompt from scratch.
- Never add a rule that only helps one recipe — check if it could hurt others.
- If adding a rule, check if an existing rule already covers the case and
  just needs tightening.
- Do not change the scoring system, runner script, or judge rubrics.

Commit the change:

    git add lib/familyrecipes/ai_import_prompt_expert.md
    git commit -m "Ralph loop: [brief description of change]"

## Step 4: Run Evaluation

    ruby test/ai_import/runner_v3.rb --prompt=ai_import_prompt_expert.md --corpus=corpus_v3

Wait for it to complete. This takes several minutes.

## Step 5: Check Convergence

Read the updated `test/ai_import/results/state.json`.

If `patience >= 2`:
1. Read the `best_iteration` label and its `prompt_sha`.
2. Restore the best prompt:

       git show <prompt_sha>:lib/familyrecipes/ai_import_prompt_expert.md > lib/familyrecipes/ai_import_prompt_expert.md

3. Commit:

       git add lib/familyrecipes/ai_import_prompt_expert.md
       git commit -m "Ralph loop: restore best prompt (iteration <label>, avg <score>)"

4. Output: <promise>EXPERT TUNED</promise>

If `patience < 2`: let the loop continue — the stop hook will feed this
prompt again and you will start from Step 1 with updated state.
