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
