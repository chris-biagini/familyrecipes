# Grocery Algorithm Tuning Log

## Iteration 0 (Baseline)

**Hypothesis:** N/A — recording current state before tuning.
**Changes:** None. Current constants:
- STARTING_INTERVAL = 7, STARTING_EASE = 1.5
- MIN_EASE = 1.1, MAX_EASE = 2.5
- EASE_BONUS = 0.05, EASE_PENALTY = 0.15
- SAFETY_MARGIN = 0.9
- Formula: `confirmed_at + (interval * SAFETY_MARGIN).to_i`
**Results:**
- S1 (Perfect user): hit=25.5% miss=65.7% annoy=8.8%
- S7 (Vacation): hit=30.7% miss=63.4% annoy=5.9%
- S9 (Holiday baker): hit=28.8% miss=64.4% annoy=6.7%
- Guardrail worst: S6 at 82.6% miss
**Assessment:** Safety margin provides only 1 day buffer for 7-day items.
Short-cycle items (eggs, milk) dominate the miss rate. Long-cycle items
(pepper, salt) perform better because the absolute buffer scales with
interval length.
**Next:** Address the safety margin formula — add a minimum absolute buffer
or use a non-linear function that gives more headroom to short intervals.
