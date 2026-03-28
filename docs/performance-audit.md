# Performance Feel Audit

**Date:** ___
**Browser:** ___
**Device:** ___

## Scoring

- **Instant** — feels like static HTML. No perceptible delay or disruption.
- **Smooth** — brief delay but no jank. Acceptable.
- **Sluggish** — noticeable pause or visual glitch. Needs investigation.
- **Broken** — delay long enough to feel wrong, or visible reflow/flash.

## Pages

| Page | Feel | FCP (ms) | Layout shifts? | Notes |
|------|------|----------|----------------|-------|
| Homepage | | | | |
| Recipe show | | | | |
| Menu | | | | |
| Groceries | | | | |
| Settings | | | | |

## Interactions

| Surface | Action | Feel | Input delay (ms) | Notes |
|---------|--------|------|-------------------|-------|
| Menu | Toggle recipe checkbox | | | |
| Menu | Toggle Quick Bite checkbox | | | |
| Menu | Click "What Should We Make?" | | | |
| Groceries | Check off to-buy item | | | |
| Groceries | Click "Have It" | | | |
| Groceries | Click "Need It" | | | |
| Groceries | Add custom item | | | |
| Recipe | Open editor dialog | | | |
| Recipe | Open nutrition editor | | | |
| Homepage | Open category editor | | | |
| Homepage | Open tag editor | | | |
| Any | Open search overlay | | | |
| Any | Type in search overlay | | | |
| Any | Navigate between pages | | | |

## ActionCable Morphs

Open two tabs. Perform an action in Tab A, observe Tab B.

| Action in Tab A | Tab B response | Feel | Notes |
|-----------------|---------------|------|-------|
| Toggle menu recipe | | | |
| Check grocery item | | | |
| Have It on grocery item | | | |
| Save recipe edit | | | |

## Static Baseline Comparison

For the worst-scoring pages, save the server HTML and compare:

```
curl -s -b cookie.txt http://rika:3030/kitchens/our-kitchen/menu > /tmp/menu-static.html
curl -s -b cookie.txt http://rika:3030/kitchens/our-kitchen/groceries > /tmp/groceries-static.html
```

| Page | Live FCP (ms) | Static FCP (ms) | Framework tax (ms) |
|------|--------------|-----------------|-------------------|
| Menu | | | |
| Groceries | | | |

## Stress Test Results

_Populated after running `rake profile:baseline KITCHEN=stress-kitchen`_

| Metric | Seed (8 recipes) | Stress (200 recipes) | Ratio |
|--------|-----------------|---------------------|-------|
| Menu time | 209ms | 494ms | 2.4x |
| Menu queries | 23 | 14 | 0.6x |
| Menu HTML | 117 KB | 388 KB | 3.3x |
| Groceries time | 116ms | 102ms | 0.9x |
| Groceries queries | 20 | 18 | 0.9x |
| Groceries HTML | 94 KB | 269 KB | 2.9x |
| Search JSON | ~3 KB | 108 KB | ~36x |

## Scaling Thresholds

_Populated from stress test analysis_

- Menu page: 494ms at 200 recipes. Scaling: sub-linear (2.4x for 25x data). HTML size (388 KB) is the main cost — rendering 200 recipe cards with availability badges. Query count actually decreased (14 vs 23), indicating eager loading scales well.
- Groceries page: 102ms at 200 recipes. Scaling: flat (0.9x). Groceries depend on meal plan selections, not total recipe count. HTML grows with catalog size (269 KB) but response time holds steady.
- Search JSON: 108 KB at 200 recipes. **Exceeds 50 KB threshold.** At ~540 bytes/recipe, 200 recipes push the embedded JSON well past the lazy-load trigger. Recommend switching to fetch-on-open for kitchens exceeding ~90 recipes.
- Turbo morph: Menu HTML 388 KB. ActionCable morphs must diff this on every broadcast. At this size, morph latency may become perceptible — monitor with real browser testing. Consider scoped morphs (per-category fragments) if morph lag appears.
