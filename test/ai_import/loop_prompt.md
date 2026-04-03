# Faithful Prompt Tuning — Ralph Loop

You are iteratively improving the faithful AI import prompt. Each iteration:
analyze what went wrong, make ONE targeted prompt edit, re-evaluate, check
convergence.

## Step 1: Read State

Read `test/ai_import/results/state.json`. Note:
- Current iteration count
- Best score and which iteration produced it
- Patience counter (stops at 2)

If state.json does not exist, this is the first iteration. Skip to Step 3.

## Step 2: Analyze Failures

Read the most recent `test/ai_import/results/iteration_*/summary.md`.

Focus on:
- Recipes with aggregate < 90 (priority targets)
- Common patterns across failures (format, fidelity, step structure)
- The worst-scoring recipe — what specifically went wrong?
- Layer 4 step structure issues — are split decisions correct?

## Step 3: Edit the Prompt

Edit `lib/familyrecipes/ai_import_prompt_faithful.md`. Rules:
- Make ONE targeted change based on the failure analysis.
- If this is the first iteration, just verify the prompt looks correct and
  make no edits.
- Never rewrite the prompt from scratch.
- Never add a rule that only helps one recipe — check if it could hurt others.
- Do not change the scoring system, runner script, or judge rubrics.

Commit the change:

    git add lib/familyrecipes/ai_import_prompt_faithful.md
    git commit -m "Ralph loop: [brief description of change]"

## Step 4: Run Evaluation

    ruby test/ai_import/runner_v3.rb --corpus=corpus_v3

Wait for it to complete. This takes several minutes.

## Step 5: Check Convergence

Read the updated `test/ai_import/results/state.json`.

If `patience >= 2`:
1. Read the `best_iteration` label and its `prompt_sha`.
2. Restore the best prompt:

       git show <prompt_sha> > lib/familyrecipes/ai_import_prompt_faithful.md

3. Commit:

       git add lib/familyrecipes/ai_import_prompt_faithful.md
       git commit -m "Ralph loop: restore best prompt (iteration <label>, avg <score>)"

4. Output: <promise>FAITHFUL TUNED</promise>

If `patience < 2`: let the loop continue — the stop hook will feed this
prompt again and you will start from Step 1 with updated state.
