# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: navigation.spec.mjs >> Navigation flows >> mobile FAB renders on small viewport
- Location: test/release/exploratory/navigation.spec.mjs:113:3

# Error details

```
Error: expect(locator).toBeVisible() failed

Locator:  locator('.fab-button')
Expected: visible
Received: hidden
Timeout:  5000ms

Call log:
  - Expect "toBeVisible" with timeout 5000ms
  - waiting for locator('.fab-button')
    9 × locator resolved to <button type="button" aria-label="Menu" class="fab-button" aria-expanded="false" data-phone-fab-target="button" data-action="phone-fab#toggle">…</button>
      - unexpected value "hidden"

```

# Page snapshot

```yaml
- generic [active] [ref=e1]:
  - navigation [ref=e2]:
    - button "Menu" [ref=e4] [cursor=pointer]:
      - img [ref=e5]
    - generic [ref=e9]:
      - link [ref=e10] [cursor=pointer]:
        - /url: /kitchens/kitchen-alpha
        - img [ref=e11]
        - generic [ref=e17]: Recipes
      - link [ref=e18] [cursor=pointer]:
        - /url: /kitchens/kitchen-alpha/ingredients
        - img [ref=e19]
        - generic [ref=e24]: Ingredients
      - link [ref=e25] [cursor=pointer]:
        - /url: /kitchens/kitchen-alpha/menu
        - img [ref=e26]
        - generic [ref=e28]: Menu
      - link [ref=e29] [cursor=pointer]:
        - /url: /kitchens/kitchen-alpha/groceries
        - img [ref=e30]
        - generic [ref=e34]: Groceries
    - button "Search recipes" [ref=e35] [cursor=pointer]:
      - img [ref=e36]
    - button "Settings" [ref=e39] [cursor=pointer]:
      - img [ref=e40]
    - link "Help" [ref=e43] [cursor=pointer]:
      - /url: https://chris-biagini.github.io/familyrecipes/recipes/
      - img [ref=e44]
  - main [ref=e47]:
    - article [ref=e48]:
      - generic [ref=e49]:
        - heading "Our Recipes" [level=1] [ref=e50]
        - paragraph [ref=e51]: A collection of our family’s favorite recipes.
      - generic [ref=e52]:
        - generic [ref=e55]:
          - generic [ref=e56]:
            - link "Test" [ref=e57] [cursor=pointer]:
              - /url: "#test"
            - text: ·
          - link "Miscellaneous" [ref=e59] [cursor=pointer]:
            - /url: "#miscellaneous"
        - generic [ref=e60]:
          - generic [ref=e61]:
            - heading "Test" [level=2] [ref=e62]
            - link "↑ top" [ref=e63] [cursor=pointer]:
              - /url: "#recipe-listings"
          - link "Test Recipe" [ref=e66] [cursor=pointer]:
            - /url: /kitchens/kitchen-alpha/recipes/test-recipe
        - generic [ref=e67]:
          - generic [ref=e68]:
            - heading "Miscellaneous" [level=2] [ref=e69]
            - link "↑ top" [ref=e70] [cursor=pointer]:
              - /url: "#recipe-listings"
          - generic [ref=e71]:
            - link "Harmless Recipe" [ref=e73] [cursor=pointer]:
              - /url: /kitchens/kitchen-alpha/recipes/harmless-recipe
            - link "Nested Recipe" [ref=e75] [cursor=pointer]:
              - /url: /kitchens/kitchen-alpha/recipes/nested-recipe
  - contentinfo [ref=e76]: vdev
```

# Test source

```ts
  24  |     // Navigate to each page and verify it loads
  25  |     await page.locator('nav').getByRole('link', { name: 'Menu' }).first().click();
  26  |     await page.waitForLoadState('networkidle');
  27  |     await expect(page.locator('h1')).toContainText('Menu');
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
> 124 |     await expect(fabButton).toBeVisible();
      |                             ^ Error: expect(locator).toBeVisible() failed
  125 | 
  126 |     await fabButton.click();
  127 | 
  128 |     const fabPanel = page.locator('.fab-panel');
  129 |     await expect(fabPanel).toBeVisible();
  130 | 
  131 |     // FAB panel should contain nav links
  132 |     const fabNavLinks = fabPanel.locator('.fab-nav-links');
  133 |     await expect(fabNavLinks).toBeVisible();
  134 | 
  135 |     // Close FAB
  136 |     await page.keyboard.press('Escape');
  137 |     await expect(fabPanel).toBeHidden();
  138 | 
  139 |     assertNoConsoleErrors();
  140 |     assertNoNetworkErrors();
  141 |   });
  142 | 
  143 |   test('help link is present in nav', async ({ page }) => {
  144 |     const assertNoConsoleErrors = trackConsoleErrors(page);
  145 |     const assertNoNetworkErrors = trackNetworkErrors(page);
  146 | 
  147 |     await loginAs(page, userIds.alice_id);
  148 |     await page.goto('/kitchens/kitchen-alpha');
  149 |     await page.waitForLoadState('networkidle');
  150 | 
  151 |     const helpLink = page.locator('nav').getByLabel('Help');
  152 |     await expect(helpLink).toBeVisible();
  153 | 
  154 |     const href = await helpLink.getAttribute('href');
  155 |     expect(href).toContain('/recipes/');
  156 | 
  157 |     assertNoConsoleErrors();
  158 |     assertNoNetworkErrors();
  159 |   });
  160 | });
  161 | 
```