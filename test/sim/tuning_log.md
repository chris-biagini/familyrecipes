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
