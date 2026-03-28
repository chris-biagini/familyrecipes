# Framework Tax Audit Report

**Generated:** 2026-03-28 15:36:51
**Runs per page:** 5 (median reported)
**Server:** http://localhost:3030
**Browser:** Headless Chromium (Playwright)

## Seed (8 recipes)

### Framework Tax

| Page | Static DomComplete | JS DomComplete | Framework Tax | All JS runs (ms) |
|------|-------------------|----------------|---------------|------------------|
| Homepage | 119ms | 924ms | **805ms** | 944, 368, 924, 696, 981 |
| Menu | 134ms | 811ms | **677ms** | 811, 281, 923, 809, 870 |
| Groceries | 150ms | 1127ms | **977ms** | 1127, 1178, 403, 508, 1212 |
| Ingredients | 283ms | 701ms | **418ms** | 701, 844, 773, 576, 583 |
| Recipe | 240ms | 698ms | **458ms** | 976, 581, 837, 698, 538 |

### Timing Breakdown (JS enabled)

| Page | Network | Parse+Exec | Async Work | Load Handlers | Total |
|------|---------|------------|------------|---------------|-------|
| Homepage | 29ms | 273ms | 622ms | 1ms | 925ms |
| Menu | 58ms | 222ms | 531ms | 1ms | 812ms |
| Groceries | 72ms | 535ms | 520ms | 1ms | 1128ms |
| Ingredients | 121ms | 561ms | 19ms | 1ms | 702ms |
| Recipe | 25ms | 545ms | 128ms | 1ms | 699ms |

### Long Tasks (>50ms main thread blocks)

**Homepage:** 3 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 88 | 214 |
| 2 | 302 | 621 |
| 3 | 988 | 307 |

**Menu:** 4 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 152 | 77 |
| 2 | 229 | 582 |
| 3 | 822 | 408 |
| 4 | 1261 | 75 |

**Groceries:** 3 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 143 | 294 |
| 2 | 438 | 185 |
| 3 | 623 | 503 |

**Ingredients:** 3 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 234 | 448 |
| 2 | 716 | 54 |
| 3 | 773 | 264 |

**Recipe:** 2 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 462 | 231 |
| 2 | 727 | 421 |

### JS Resources Loaded

**Homepage:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 6 | 35 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 3 | 82 |
| src-VHY7BWOU.js | cached | 9.3 | 4 | 111 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 175 | 210 |
| registry-Y22OGGUX.js | cached | 3.0 | 170 | 214 |
| auto_dash-DNFLZABB.js | cached | 0.4 | 170 | 214 |
| dist-2BJIGAD4.js | cached | 1.5 | 169 | 215 |
| chunk-3JPQEHXL.js | cached | 220.5 | 13 | 932 |
| chunk-I5URIM62.js | cached | 70.5 | 12 | 932 |

**Menu:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 9 | 64 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 1 | 149 |
| src-VHY7BWOU.js | cached | 9.3 | 24 | 167 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 2 | 826 |
| registry-Y22OGGUX.js | cached | 3.0 | 5 | 829 |
| auto_dash-DNFLZABB.js | cached | 0.4 | 11 | 829 |
| dist-2BJIGAD4.js | cached | 1.5 | 11 | 829 |
| chunk-I5URIM62.js | cached | 70.5 | 5 | 1238 |
| chunk-3JPQEHXL.js | cached | 220.5 | 6 | 1240 |

**Groceries:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 8 | 70 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 4 | 120 |
| src-VHY7BWOU.js | cached | 9.3 | 3 | 450 |

**Ingredients:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 6 | 127 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 1 | 205 |
| src-VHY7BWOU.js | cached | 9.3 | 5 | 273 |

**Recipe:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 11 | 33 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 2 | 99 |
| src-VHY7BWOU.js | cached | 9.3 | 5 | 512 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 5 | 730 |
| registry-Y22OGGUX.js | cached | 3.0 | 9 | 732 |
| auto_dash-DNFLZABB.js | cached | 0.4 | 9 | 732 |
| dist-2BJIGAD4.js | cached | 1.5 | 9 | 798 |
| chunk-I5URIM62.js | cached | 70.5 | 1 | 1154 |
| chunk-3JPQEHXL.js | cached | 220.5 | 2 | 1156 |

### CodeMirror Prefetch Analysis

- **Homepage:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-3JPQEHXL.js, chunk-I5URIM62.js. Last response at 945ms, DomComplete at 924ms. AFTER DomComplete — does not inflate DomComplete directly
- **Menu:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-I5URIM62.js, chunk-3JPQEHXL.js. Last response at 1246ms, DomComplete at 811ms. AFTER DomComplete — does not inflate DomComplete directly
- **Groceries:** Loaded chunk-RNFM7RMJ.js. Last response at 124ms, DomComplete at 1127ms. BEFORE DomComplete — contributes to framework tax measurement
- **Ingredients:** Loaded chunk-RNFM7RMJ.js. Last response at 206ms, DomComplete at 701ms. BEFORE DomComplete — contributes to framework tax measurement
- **Recipe:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-I5URIM62.js, chunk-3JPQEHXL.js. Last response at 1159ms, DomComplete at 698ms. AFTER DomComplete — does not inflate DomComplete directly

## Stress (200 recipes)

### Framework Tax

| Page | Static DomComplete | JS DomComplete | Framework Tax | All JS runs (ms) |
|------|-------------------|----------------|---------------|------------------|
| Homepage | 226ms | 891ms | **665ms** | 891, 857, 892, 859, 901 |
| Menu | 274ms | 430ms | **156ms** | 430, 392, 601, 367, 474 |
| Groceries | 238ms | 794ms | **556ms** | 767, 246, 829, 1132, 794 |
| Ingredients | 687ms | 2248ms | **1561ms** | 2129, 2268, 2248, 2327, 1968 |
| Recipe | 113ms | 721ms | **608ms** | 909, 862, 721, 711, 576 |

### Timing Breakdown (JS enabled)

| Page | Network | Parse+Exec | Async Work | Load Handlers | Total |
|------|---------|------------|------------|---------------|-------|
| Homepage | 41ms | 249ms | 601ms | 0ms | 891ms |
| Menu | 126ms | 281ms | 23ms | 1ms | 431ms |
| Groceries | 63ms | 204ms | 527ms | 1ms | 795ms |
| Ingredients | 531ms | 1694ms | 23ms | 0ms | 2248ms |
| Recipe | 25ms | 547ms | 149ms | 0ms | 721ms |

### Long Tasks (>50ms main thread blocks)

**Homepage:** 4 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 101 | 330 |
| 2 | 432 | 458 |
| 3 | 935 | 344 |
| 4 | 1289 | 83 |

**Menu:** 4 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 149 | 51 |
| 2 | 209 | 52 |
| 3 | 286 | 135 |
| 4 | 433 | 52 |

**Groceries:** 4 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 174 | 92 |
| 2 | 267 | 526 |
| 3 | 810 | 61 |
| 4 | 875 | 303 |

**Ingredients:** 6 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 715 | 81 |
| 2 | 807 | 96 |
| 3 | 973 | 112 |
| 4 | 1096 | 117 |
| 5 | 1259 | 96 |
| 6 | 1355 | 870 |

**Recipe:** 4 long task(s)

| # | Start (ms) | Duration (ms) |
|---|-----------|---------------|
| 1 | 108 | 486 |
| 2 | 597 | 116 |
| 3 | 721 | 50 |
| 4 | 879 | 429 |

### JS Resources Loaded

**Homepage:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 7 | 44 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 2 | 97 |
| src-VHY7BWOU.js | cached | 9.3 | 4 | 139 |
| editor_setup-55VNW5QV.js | cached | 236.2 | 73 | 270 |
| registry-Y22OGGUX.js | cached | 3.0 | 69 | 274 |
| auto_dash-DNFLZABB.js | cached | 0.4 | 68 | 275 |
| dist-2BJIGAD4.js | cached | 1.5 | 66 | 277 |
| chunk-I5URIM62.js | cached | 70.5 | 38 | 903 |
| chunk-3JPQEHXL.js | cached | 220.5 | 42 | 903 |

**Menu:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 7 | 130 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 1 | 261 |
| src-VHY7BWOU.js | cached | 9.3 | 4 | 316 |
| registry-Y22OGGUX.js | cached | 3.0 | 2 | 1030 |
| auto_dash-DNFLZABB.js | cached | 0.4 | 4 | 1030 |
| dist-2BJIGAD4.js | cached | 1.5 | 4 | 1030 |

**Groceries:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 7 | 91 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 1 | 148 |
| src-VHY7BWOU.js | cached | 9.3 | 1 | 188 |

**Ingredients:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 9 | 624 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 3 | 797 |
| src-VHY7BWOU.js | cached | 9.3 | 5 | 1551 |

**Recipe:**

| File | Transfer (KB) | Decoded (KB) | Duration (ms) | Start (ms) |
|------|--------------|-------------|---------------|-----------|
| application-b4168199.js | cached | 237.9 | 5 | 32 |
| chunk-RNFM7RMJ.js | cached | 0.2 | 3 | 108 |
| src-VHY7BWOU.js | cached | 9.3 | 3 | 619 |

### CodeMirror Prefetch Analysis

- **Homepage:** Loaded chunk-RNFM7RMJ.js, editor_setup-55VNW5QV.js, chunk-I5URIM62.js, chunk-3JPQEHXL.js. Last response at 945ms, DomComplete at 891ms. AFTER DomComplete — does not inflate DomComplete directly
- **Menu:** Loaded chunk-RNFM7RMJ.js. Last response at 263ms, DomComplete at 430ms. BEFORE DomComplete — contributes to framework tax measurement
- **Groceries:** Loaded chunk-RNFM7RMJ.js. Last response at 149ms, DomComplete at 794ms. BEFORE DomComplete — contributes to framework tax measurement
- **Ingredients:** Loaded chunk-RNFM7RMJ.js. Last response at 800ms, DomComplete at 2248ms. BEFORE DomComplete — contributes to framework tax measurement
- **Recipe:** Loaded chunk-RNFM7RMJ.js. Last response at 111ms, DomComplete at 721ms. BEFORE DomComplete — contributes to framework tax measurement

## Top Contributors (Analysis)

_Fill in after reviewing the data above._

1. 
2. 
3. 
