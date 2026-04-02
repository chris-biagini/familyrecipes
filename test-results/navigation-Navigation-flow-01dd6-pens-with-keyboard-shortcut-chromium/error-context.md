# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: navigation.spec.mjs >> Navigation flows >> search overlay opens with / keyboard shortcut
- Location: test/release/exploratory/navigation.spec.mjs:71:3

# Error details

```
Error: JS console errors detected

expect(received).toEqual(expected) // deep equality

- Expected  - 1
+ Received  + 5

- Array []
+ Array [
+   "Failed to load resource: the server responded with a status of 404 (Not Found)",
+   "Failed to load resource: the server responded with a status of 403 (Forbidden)",
+   "A bad HTTP response code (422) was received when fetching the script.",
+ ]
```

# Page snapshot

```yaml
- generic [active] [ref=e1]:
  - navigation [ref=e2]:
    - generic [ref=e4]:
      - link "Recipes" [ref=e5] [cursor=pointer]:
        - /url: /kitchens/kitchen-alpha
        - img [ref=e6]
        - generic [ref=e12]: Recipes
      - link "Ingredients" [ref=e13] [cursor=pointer]:
        - /url: /kitchens/kitchen-alpha/ingredients
        - img [ref=e14]
        - generic [ref=e19]: Ingredients
      - link "Menu" [ref=e20] [cursor=pointer]:
        - /url: /kitchens/kitchen-alpha/menu
        - img [ref=e21]
        - generic [ref=e23]: Menu
      - link "Groceries" [ref=e24] [cursor=pointer]:
        - /url: /kitchens/kitchen-alpha/groceries
        - img [ref=e25]
        - generic [ref=e29]: Groceries
    - button "Search recipes" [ref=e30] [cursor=pointer]:
      - img [ref=e31]
    - button "Settings" [ref=e34] [cursor=pointer]:
      - img [ref=e35]
    - link "Help" [ref=e38] [cursor=pointer]:
      - /url: https://chris-biagini.github.io/familyrecipes/recipes/
      - img [ref=e39]
  - main [ref=e42]:
    - article [ref=e43]:
      - generic [ref=e44]:
        - heading "Our Recipes" [level=1] [ref=e45]
        - paragraph [ref=e46]: A collection of our family’s favorite recipes.
      - generic [ref=e47]:
        - generic [ref=e50]:
          - generic [ref=e51]:
            - link "Test" [ref=e52] [cursor=pointer]:
              - /url: "#test"
            - text: ·
          - link "Miscellaneous" [ref=e54] [cursor=pointer]:
            - /url: "#miscellaneous"
        - generic [ref=e55]:
          - generic [ref=e56]:
            - heading "Test" [level=2] [ref=e57]
            - link "↑ top" [ref=e58] [cursor=pointer]:
              - /url: "#recipe-listings"
          - link "Test Recipe" [ref=e61] [cursor=pointer]:
            - /url: /kitchens/kitchen-alpha/recipes/test-recipe
        - generic [ref=e62]:
          - generic [ref=e63]:
            - heading "Miscellaneous" [level=2] [ref=e64]
            - link "↑ top" [ref=e65] [cursor=pointer]:
              - /url: "#recipe-listings"
          - generic [ref=e66]:
            - link "Harmless Recipe" [ref=e68] [cursor=pointer]:
              - /url: /kitchens/kitchen-alpha/recipes/harmless-recipe
            - link "Nested Recipe" [ref=e70] [cursor=pointer]:
              - /url: /kitchens/kitchen-alpha/recipes/nested-recipe
  - contentinfo [ref=e71]: vdev
```

# Test source

```ts
  1  | // Shared helpers for release exploratory tests.
  2  | // Assumes a running dev server on localhost:3030 with MULTI_KITCHEN=true.
  3  | 
  4  | import { expect } from '@playwright/test';
  5  | 
  6  | /**
  7  |  * Log in as a specific user by hitting the dev login endpoint.
  8  |  * @param {import('@playwright/test').Page} page
  9  |  * @param {number} userId
  10 |  */
  11 | export async function loginAs(page, userId) {
  12 |   await page.goto(`/dev_login?id=${userId}`);
  13 |   await page.waitForLoadState('networkidle');
  14 | }
  15 | 
  16 | /**
  17 |  * Attach a console error listener. Returns a function that asserts no errors.
  18 |  * @param {import('@playwright/test').Page} page
  19 |  * @returns {function} assertNoErrors — call at end of test
  20 |  */
  21 | export function trackConsoleErrors(page) {
  22 |   const errors = [];
  23 |   page.on('console', (msg) => {
  24 |     if (msg.type() === 'error') {
  25 |       errors.push(msg.text());
  26 |     }
  27 |   });
  28 |   return () => {
> 29 |     expect(errors, 'JS console errors detected').toEqual([]);
     |                                                  ^ Error: JS console errors detected
  30 |   };
  31 | }
  32 | 
  33 | /**
  34 |  * Attach a network failure listener for 4xx/5xx responses.
  35 |  * @param {import('@playwright/test').Page} page
  36 |  * @returns {function} assertNoNetworkErrors
  37 |  */
  38 | export function trackNetworkErrors(page) {
  39 |   const failures = [];
  40 |   page.on('response', (response) => {
  41 |     const status = response.status();
  42 |     if (status >= 400 && !response.url().includes('favicon')) {
  43 |       failures.push(`${status} ${response.url()}`);
  44 |     }
  45 |   });
  46 |   return () => {
  47 |     expect(failures, 'Network errors detected').toEqual([]);
  48 |   };
  49 | }
  50 | 
  51 | /**
  52 |  * Read the user IDs file written by the security seed script.
  53 |  */
  54 | export async function readUserIds() {
  55 |   const fs = await import('fs/promises');
  56 |   const path = await import('path');
  57 |   const idsPath = path.join(process.cwd(), 'test', 'security', 'user_ids.json');
  58 |   const content = await fs.readFile(idsPath, 'utf-8');
  59 |   return JSON.parse(content);
  60 | }
  61 | 
```