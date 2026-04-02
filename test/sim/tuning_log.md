# Grocery Algorithm Tuning Log (Round 3)

Previous rounds: round 1 tuned safety margin, round 2 added weighted blending +
growth cap. This round: re-tune all constants after adding burst detection.

## Iteration 0 (Baseline — post burst detection)

**Hypothesis:** N/A — recording state after adding burst detection.
**Changes:** None. Current constants:
- STARTING_INTERVAL = 7, STARTING_EASE = 1.5
- MIN_EASE = 1.05, MAX_EASE = 2.5
- EASE_BONUS = 0.05, EASE_PENALTY = 0.20
- SAFETY_MARGIN = 0.78, MIN_BUFFER = 2
- BLEND_WEIGHT = 0.75, MAX_GROWTH_FACTOR = 1.3
- BURST_THRESHOLD = 0.5, MIN_ESTABLISHED_INTERVAL = 14
**Results:**
- S1 (Perfect user): hit=46.1% miss=40.2% annoy=13.7%
- S7 (Vacation): hit=43.6% miss=47.5% annoy=8.9%
- S9 (Holiday baker): hit=41.3% miss=43.3% annoy=15.4%
- Guardrail worst: S11 at 79.8% miss
**Assessment:** Burst detection improved S9 dramatically (annoy 18.3→15.4%, miss
49.0→43.3%, hit 32.7→41.3%). However, BURST_THRESHOLD=0.5 is too aggressive —
S7 miss spiked from 39.6% to 47.5%, S8 from 48.5% to 71.1%. The threshold
catches legitimate depletions during vacations and disruptions, not just bursts.
S11 guardrail at 79.8% is also concerning (was 57.0%).
**Next:** Lower BURST_THRESHOLD toward 0.3–0.4 to reduce false positives. Also
try MIN_EASE=1.1 now that S9 burst is handled — the ME tradeoff from round 2
may no longer apply.
