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
| Menu time | 209ms | | |
| Menu queries | 23 | | |
| Menu HTML | 117 KB | | |
| Groceries time | 116ms | | |
| Groceries queries | 20 | | |
| Groceries HTML | 94 KB | | |
| Search JSON | ~3 KB | | |

## Scaling Thresholds

_Populated from stress test analysis_

- Menu page: ___ms at 200 recipes. Scaling: ___.
- Groceries page: ___ms at 200 recipes. Scaling: ___.
- Search JSON: ___ KB at 200 recipes. Threshold (50 KB): ___.
- Turbo morph: Menu HTML ___ KB. Impact: ___.
