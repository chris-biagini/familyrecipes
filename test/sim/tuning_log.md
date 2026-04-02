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

## Iteration 1

**Hypothesis:** Add MIN_BUFFER=2 so short-cycle items (eggs, milk) get at least
2 days of IC warning instead of 1. Formula: `min(interval * 0.9, interval - 2)`.
**Changes:**
- Added MIN_BUFFER = 2
- Formula: `[interval * SAFETY_MARGIN, interval - MIN_BUFFER].min.to_i`
- Updated all three locations (Ruby on_hand?, SQL active scope, sim Entry)
**Results:**
- S1 (Perfect user): hit=29.4% miss=59.8% annoy=10.8%
- S7 (Vacation): hit=30.7% miss=61.4% annoy=7.9%
- S9 (Holiday baker): hit=31.7% miss=59.6% annoy=8.7%
- Guardrail worst: S6 at 81.4% miss
**Assessment:** All core scenarios improved on miss rate (~4-5pp drop). Hit rates
improved modestly (+1-3pp). Annoyance increased slightly but well within 15% cap.
Still far from targets (need hit≥50%, miss≤40%). The 2-day buffer helps but
isn't enough — the algorithm also converges too slowly.
**Next:** Increase MIN_BUFFER to 3 and lower SAFETY_MARGIN to 0.8 to give
more buffer across all interval lengths. Also increase EASE_PENALTY from
0.15 to 0.20 to speed convergence on depletion events.
