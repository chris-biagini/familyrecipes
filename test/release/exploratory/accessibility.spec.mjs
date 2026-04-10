// Accessibility spot-check using axe-core on key pages.
// Runs WCAG 2.1 AA rules via AxeBuilder. Critical/serious violations fail
// the test; moderate/minor are logged as warnings only.
//
// Requires a running dev server: bin/dev
// Requires security kitchens seeded: bin/rails runner test/security/seed_security_kitchens.rb

import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { loginAs, readUserIds } from './setup.mjs';

const PAGES_TO_CHECK = [
  { name: 'Recipe index', path: '/recipes' },
  { name: 'Groceries', path: '/groceries' },
  { name: 'Ingredients', path: '/ingredients' },
  { name: 'Settings (via dialog)', path: '/' },
];

test.describe('Accessibility spot-check (WCAG 2.1 AA)', () => {
  let userId;
  let kitchenSlug;

  test.beforeAll(async () => {
    const ids = await readUserIds();
    userId = ids.alice_id;
    kitchenSlug = 'kitchen-alpha';
  });

  for (const pageInfo of PAGES_TO_CHECK) {
    test(`${pageInfo.name} has no critical a11y violations`, async ({ page }) => {
      await loginAs(page, userId);
      await page.goto(`/kitchens/${kitchenSlug}${pageInfo.path}`);
      await page.waitForLoadState('networkidle');

      const results = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
        .analyze();

      const critical = results.violations.filter(v =>
        v.impact === 'critical' || v.impact === 'serious'
      );

      if (critical.length > 0) {
        const summary = critical.map(v =>
          `[${v.impact}] ${v.id}: ${v.description} (${v.nodes.length} instance(s))`
        ).join('\n');
        expect.soft(critical, `Critical a11y violations on ${pageInfo.name}:\n${summary}`).toEqual([]);
      }

      // Log moderate/minor as warnings
      const warnings = results.violations.filter(v =>
        v.impact === 'moderate' || v.impact === 'minor'
      );
      if (warnings.length > 0) {
        console.log(`\n  A11y warnings on ${pageInfo.name}:`);
        warnings.forEach(v => {
          console.log(`    [${v.impact}] ${v.id}: ${v.description}`);
        });
      }
    });
  }
});
