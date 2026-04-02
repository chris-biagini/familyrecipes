# Grocery Algorithm Tuning Log (Round 2)

Previous round: iterations 0–3 tuned safety margin formula and ease constants.
This round: re-tune all constants after adding weighted blending + growth cap.

## Iteration 0 (Baseline — post algorithm change)

**Hypothesis:** N/A — recording state after adding BLEND_WEIGHT and MAX_GROWTH_FACTOR.
**Changes:** None. Current constants:
- STARTING_INTERVAL = 7, STARTING_EASE = 1.5
- MIN_EASE = 1.05, MAX_EASE = 2.5
- EASE_BONUS = 0.03, EASE_PENALTY = 0.20
- SAFETY_MARGIN = 0.78, MIN_BUFFER = 2
- BLEND_WEIGHT = 0.65, MAX_GROWTH_FACTOR = 1.3
- Safety margin formula: `min(interval * 0.78, interval - 2)`
- Blend formula: `observed * 0.65 + interval * 0.35`
- Growth cap: `interval * min(ease, 1.3)`
**Results:**
- S1 (Perfect user): hit=38.2% miss=46.1% annoy=15.7%
- S7 (Vacation): hit=44.6% miss=39.6% annoy=15.8%
- S9 (Holiday baker): hit=30.8% miss=51.0% annoy=18.3%
- Guardrail worst: S6 at 66.3% miss
**Assessment:** S7 miss rate already passes (39.6% ≤ 40%) before any tuning!
The weighted blending and growth cap have tightened convergence. However,
annoyance is elevated across all three core scenarios (15.7–18.3%), suggesting
the safety margin or MIN_BUFFER may be too aggressive now that intervals
converge faster. The tighter oscillation band means less buffer is needed.
**Next:** Try raising SAFETY_MARGIN back toward 0.80–0.82 since the tighter
convergence means less safety buffer is needed. Also explore BLEND_WEIGHT
values between 0.60–0.75 to find the miss/annoyance sweet spot.

## Iteration 1

**Hypothesis:** Raise BLEND_WEIGHT to 0.75 for tighter convergence. Revert
EASE_BONUS to 0.05 for faster post-depletion recovery. SM=0.80 and SM=0.82
were tested and rejected (killed miss rates due to milk sensitivity at interval=10).
**Changes:**
- BLEND_WEIGHT=0.75 (was 0.65), EASE_BONUS=0.05 (was 0.03)
- All other constants unchanged
**Results:**
- S1 (Perfect user): hit=46.1% miss=40.2% annoy=13.7%
- S7 (Vacation): hit=48.5% miss=39.6% annoy=11.9%
- S9 (Holiday baker): hit=32.7% miss=49.0% annoy=18.3%
- Guardrail worst: S6 at 62.8% miss
**Assessment:** S7 passes miss AND annoyance! S1 annoyance dropped from 15.7%
to 13.7% (passes!). S1 miss is 40.2% — just 0.2pp over target. S9 remains
difficult (burst consumption → slow recovery → persistent annoyance). Higher
EASE_BONUS helped annoyance dramatically by speeding recovery from depletions.
**Next:** Try STARTING_EASE=1.3 to reduce ease-after-first-depletion (1.24→1.08),
which should shrink the second-cycle overshoot. The MGF=1.3 cap means first-cycle
growth is identical regardless of STARTING_EASE, so long-cycle items don't suffer.

## Iteration 2

**Hypothesis:** Explored MIN_EASE as a lever to control burst recovery speed (S9).
Tested SM=0.82 (annoy ✓ but miss ✗), SM=0.80 (same), BW=0.80 (too aggressive),
SE=1.3 (hurt long-cycle items), ME=1.07/1.09/1.1. Found that ME=1.1 fixes S9
annoyance (14.4%) but raises S1/S7 miss to 42.2%. Also tested ME=1.1+BW=0.78 —
S9 annoy=13.5% ✓ but S1 miss=42.2% ✗.
**Changes:** Explored many configs, reverted to iteration 1 best:
- BW=0.75, EB=0.05, SM=0.78, SE=1.5, ME=1.05, MGF=1.3
**Results:**
- S1 (Perfect user): hit=46.1% miss=40.2% annoy=13.7%
- S7 (Vacation): hit=48.5% miss=39.6% annoy=11.9%
- S9 (Holiday baker): hit=32.7% miss=49.0% annoy=18.3%
- Guardrail worst: S6 at 62.8% miss
**Assessment:** Found a trilemma: MIN_EASE controls S1 miss ↔ S9 annoyance tradeoff.
ME=1.05 gives tight oscillation (S1/S7 miss pass) but slow burst recovery (S9
annoy 18.3%). ME=1.1 gives fast recovery (S9 annoy 14.4%) but wider oscillation
(S1/S7 miss 42.2%). No intermediate ME value achieves both. The algorithm cannot
distinguish "normal depletion" from "burst depletion" — a burst-aware mechanism
would be needed.

## Iteration 3 (Stalling)

Last 3 iterations (1, 2, and this one) have explored SM, BW, ME, SE, EB, EP,
and MGF across dozens of configurations. The best achievable config passes
S1 annoyance + S7 miss + S7 annoyance but misses S1 miss by 0.2pp and S9
annoyance by 3.3pp. The remaining gap is structural: MIN_EASE creates a
S1-miss ↔ S9-annoyance tradeoff that constants alone cannot resolve.

**Best final config:** BW=0.75, EB=0.05, SM=0.78, SE=1.5, ME=1.05, MGF=1.3, EP=0.20
**Best final results:**
- S1: hit=46.1% miss=40.2% annoy=13.7% (miss 0.2pp over)
- S7: hit=48.5% miss=39.6% annoy=11.9% (miss ✓, annoy ✓)
- S9: hit=32.7% miss=49.0% annoy=18.3% (both over)
- Guardrail: S6 at 62.8% (✓, well under 85%)
