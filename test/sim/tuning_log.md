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

## Iteration 2

**Hypothesis:** Explored multiple combinations to find the miss/annoyance sweet spot.
Tested: SM=0.8/MB=3 (good miss, too much annoyance), SM=0.75/MB=2 (more medium
buffer, annoyance spike), STARTING_EASE=1.2 (hurt long-cycle items), EASE_BONUS=0.08
(more overshoot), log2 formula (great miss rates but 19-20% annoyance), EP=0.25 and
EP=0.30 (diminishing returns). Per-item analysis revealed eggs (7-day) and milk
(10-day) are the primary bottleneck due to interval oscillation (7→10.85→blend 8.9→...).
**Changes:** Settled on SM=0.8, MB=2, EP=0.20 as best balance:
- SAFETY_MARGIN=0.8, MIN_BUFFER=2, EASE_PENALTY=0.20
- STARTING_EASE=1.5, EASE_BONUS=0.05, MIN_EASE=1.1
- Formula: `min(interval * 0.8, interval - 2)`
**Results:**
- S1 (Perfect user): hit=40.2% miss=47.1% annoy=12.7%
- S7 (Vacation): hit=42.6% miss=47.5% annoy=9.9%
- S9 (Holiday baker): hit=34.6% miss=53.8% annoy=11.5%
- Guardrail worst: S6 at 68.6% miss
**Assessment:** Miss rates improved 10-18pp from baseline. Annoyance well
controlled. But still ~7pp away from 40% miss target on S1/S7, ~14pp on S9.
The key finding: the interval oscillation (eggs 7→10.85→8.9→10.8) means IC
alternates between "just right" and "too late". Eggs per-item: 22% hit, 56%
miss, 22% annoy. Butter: 57% hit but 19% annoy. Flour/pepper: >60% hit.
**Next:** Try a two-tier buffer formula using `max(MB, log2(interval) * scale)`
that gives larger absolute buffer for medium intervals (where eggs oscillate)
while using the SM cap to prevent annoyance for properly-converged long items.

## Iteration 3

**Hypothesis:** Explored many formula and constant variants to break the miss/annoyance
tradeoff. Key finding: SM=0.78 gives effective=10 for interval=14 (catches butter
depletions) while SM=0.79+ gives effective=11 (misses them). EB=0.03 slows post-first-
cycle growth, tightening eggs oscillation from 8.6-10.2 to 8.3-9.6. ME=1.05 lets ease
drop lower faster. Tested: log2 formula, tapered extra buffer, SM+offset formula,
STARTING_INTERVAL=8 (conformance failure), ME=1.0 (hurt S9).
**Changes:** Best config found:
- SAFETY_MARGIN=0.78, MIN_BUFFER=2
- STARTING_EASE=1.5, EASE_BONUS=0.03, EASE_PENALTY=0.20, MIN_EASE=1.05
- Formula: `min(interval * 0.78, interval - 2)`
**Results:**
- S1 (Perfect user): hit=45.1% miss=39.2% annoy=15.7%
- S7 (Vacation): hit=45.5% miss=40.6% annoy=13.9%
- S9 (Holiday baker): hit=41.3% miss=42.3% annoy=16.3%
- Guardrail worst: S6 at 64.0% miss
**Assessment:** S1 miss rate now passes (39.2% ≤ 40%)! But S1 annoyance is 15.7%
(0.7pp over 15% target). S7 miss is 0.6pp over, S9 needs both miss and annoyance
work. The miss/annoyance tradeoff is fundamentally tied to butter at interval=14:
effective=10 gives buffer=4 days (28.6% of 14 → annoying) but catches fuzz-early
depletions. No formula change can fix both without changing the core algorithm.
**Next:** The last 3 iterations have all hovered around the same miss/annoyance
tradeoff boundary. Constants are fine-tuned. The remaining gap (0.7pp annoyance
on S1, ~2pp miss on S7/S9) appears structural given the constraint that only
constants and the safety margin formula can change. Stalling.
