# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: navigation.spec.mjs >> Navigation flows >> main nav links are present and functional
- Location: test/release/exploratory/navigation.spec.mjs:11:3

# Error details

```
Error: expect(locator).toContainText(expected) failed

Locator: locator('h1')
Expected substring: "Menu"
Timeout: 5000ms
Error: element(s) not found

Call log:
  - Expect "toContainText" with timeout 5000ms
  - waiting for locator('h1')

```

# Test source

```ts
  1   | import { test, expect } from '@playwright/test';
  2   | import { loginAs, trackConsoleErrors, trackNetworkErrors, readUserIds } from './setup.mjs';
  3   | 
  4   | let userIds;
  5   | 
  6   | test.beforeAll(async () => {
  7   |   userIds = await readUserIds();
  8   | });
  9   | 
  10  | test.describe('Navigation flows', () => {
  11  |   test('main nav links are present and functional', async ({ page }) => {
  12  |     const assertNoConsoleErrors = trackConsoleErrors(page);
  13  |     const assertNoNetworkErrors = trackNetworkErrors(page);
  14  | 
  15  |     await loginAs(page, userIds.alice_id);
  16  |     await page.goto('/kitchens/kitchen-alpha');
  17  |     await page.waitForLoadState('networkidle');
  18  | 
  19  |     for (const label of ['Recipes', 'Ingredients', 'Menu', 'Groceries']) {
  20  |       const link = page.locator('nav').getByRole('link', { name: label }).first();
  21  |       await expect(link).toBeVisible();
  22  |     }
  23  | 
  24  |     // Navigate to each page and verify it loads
  25  |     await page.locator('nav').getByRole('link', { name: 'Menu' }).first().click();
  26  |     await page.waitForLoadState('networkidle');
> 27  |     await expect(page.locator('h1')).toContainText('Menu');
      |                                      ^ Error: expect(locator).toContainText(expected) failed
  28  | 
  29  |     await page.locator('nav').getByRole('link', { name: 'Groceries' }).first().click();
  30  |     await page.waitForLoadState('networkidle');
  31  |     await expect(page.locator('h1')).toContainText('Groceries');
  32  | 
  33  |     await page.locator('nav').getByRole('link', { name: 'Ingredients' }).first().click();
  34  |     await page.waitForLoadState('networkidle');
  35  |     await expect(page.locator('h1')).toContainText('Ingredients');
  36  | 
  37  |     await page.locator('nav').getByRole('link', { name: 'Recipes' }).first().click();
  38  |     await page.waitForLoadState('networkidle');
  39  |     await expect(page.locator('h1')).toBeVisible();
  40  | 
  41  |     assertNoConsoleErrors();
  42  |     assertNoNetworkErrors();
  43  |   });
  44  | 
  45  |   test('search overlay opens and closes', async ({ page }) => {
  46  |     const assertNoConsoleErrors = trackConsoleErrors(page);
  47  |     const assertNoNetworkErrors = trackNetworkErrors(page);
  48  | 
  49  |     await loginAs(page, userIds.alice_id);
  50  |     await page.goto('/kitchens/kitchen-alpha');
  51  |     await page.waitForLoadState('networkidle');
  52  | 
  53  |     const searchButton = page.locator('nav').getByLabel('Search recipes');
  54  |     await expect(searchButton).toBeVisible();
  55  |     await searchButton.click();
  56  | 
  57  |     const searchDialog = page.locator('.search-overlay');
  58  |     await expect(searchDialog).toBeVisible();
  59  | 
  60  |     const searchInput = searchDialog.locator('.search-input');
  61  |     await expect(searchInput).toBeVisible();
  62  | 
  63  |     // Close with Escape
  64  |     await page.keyboard.press('Escape');
  65  |     await expect(searchDialog).toBeHidden();
  66  | 
  67  |     assertNoConsoleErrors();
  68  |     assertNoNetworkErrors();
  69  |   });
  70  | 
  71  |   test('search overlay opens with / keyboard shortcut', async ({ page }) => {
  72  |     const assertNoConsoleErrors = trackConsoleErrors(page);
  73  |     const assertNoNetworkErrors = trackNetworkErrors(page);
  74  | 
  75  |     await loginAs(page, userIds.alice_id);
  76  |     await page.goto('/kitchens/kitchen-alpha');
  77  |     await page.waitForLoadState('networkidle');
  78  | 
  79  |     await page.keyboard.press('/');
  80  | 
  81  |     const searchDialog = page.locator('.search-overlay');
  82  |     await expect(searchDialog).toBeVisible();
  83  | 
  84  |     await page.keyboard.press('Escape');
  85  |     await expect(searchDialog).toBeHidden();
  86  | 
  87  |     assertNoConsoleErrors();
  88  |     assertNoNetworkErrors();
  89  |   });
  90  | 
  91  |   test('search overlay shows results for query', async ({ page }) => {
  92  |     const assertNoConsoleErrors = trackConsoleErrors(page);
  93  |     const assertNoNetworkErrors = trackNetworkErrors(page);
  94  | 
  95  |     await loginAs(page, userIds.alice_id);
  96  |     await page.goto('/kitchens/kitchen-alpha');
  97  |     await page.waitForLoadState('networkidle');
  98  | 
  99  |     await page.keyboard.press('/');
  100 | 
  101 |     const searchInput = page.locator('.search-input');
  102 |     await searchInput.fill('test');
  103 | 
  104 |     const results = page.locator('.search-results');
  105 |     await expect(results).toBeVisible();
  106 | 
  107 |     await page.keyboard.press('Escape');
  108 | 
  109 |     assertNoConsoleErrors();
  110 |     assertNoNetworkErrors();
  111 |   });
  112 | 
  113 |   test('mobile FAB renders on small viewport', async ({ page }) => {
  114 |     const assertNoConsoleErrors = trackConsoleErrors(page);
  115 |     const assertNoNetworkErrors = trackNetworkErrors(page);
  116 | 
  117 |     await page.setViewportSize({ width: 375, height: 667 });
  118 | 
  119 |     await loginAs(page, userIds.alice_id);
  120 |     await page.goto('/kitchens/kitchen-alpha');
  121 |     await page.waitForLoadState('networkidle');
  122 | 
  123 |     const fabButton = page.locator('.fab-button');
  124 |     await expect(fabButton).toBeVisible();
  125 | 
  126 |     await fabButton.click();
  127 | 
```