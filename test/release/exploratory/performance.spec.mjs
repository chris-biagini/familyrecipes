import { test } from '@playwright/test';
import { loginAs, readUserIds } from './setup.mjs';
import { writeFileSync } from 'fs';
import { join } from 'path';

const PAGES_TO_MEASURE = [
  { name: 'Recipe index', path: '/recipes' },
  { name: 'Groceries', path: '/groceries' },
  { name: 'Ingredients', path: '/ingredients' },
];

test.describe('Performance baseline', () => {
  let userId;
  let kitchenSlug;
  const measurements = {};

  test.beforeAll(async () => {
    const ids = await readUserIds();
    userId = ids.alice_id;
    kitchenSlug = 'kitchen-alpha';
  });

  for (const pageInfo of PAGES_TO_MEASURE) {
    test(`measure ${pageInfo.name}`, async ({ page }) => {
      await loginAs(page, userId);

      await page.goto(`/kitchens/${kitchenSlug}${pageInfo.path}`);
      await page.waitForLoadState('networkidle');

      const timing = await page.evaluate(() => {
        const nav = performance.getEntriesByType('navigation')[0];
        const resources = performance.getEntriesByType('resource');
        return {
          domContentLoaded: Math.round(nav.domContentLoadedEventEnd - nav.startTime),
          loadComplete: Math.round(nav.loadEventEnd - nav.startTime),
          resourceCount: resources.length,
          totalTransferSize: resources.reduce((sum, r) => sum + (r.transferSize || 0), 0),
        };
      });

      measurements[pageInfo.name] = timing;
      console.log(`  ${pageInfo.name}: DOM=${timing.domContentLoaded}ms, ` +
        `Load=${timing.loadComplete}ms, ` +
        `Resources=${timing.resourceCount}, ` +
        `Transfer=${Math.round(timing.totalTransferSize / 1024)}KB`);
    });
  }

  test.afterAll(async () => {
    const date = new Date().toISOString().split('T')[0];
    const outPath = join(process.cwd(), 'tmp', `perf_baseline_${date}.json`);
    const report = {
      date: new Date().toISOString(),
      commit: process.env.GIT_SHA || 'unknown',
      measurements,
    };
    writeFileSync(outPath, JSON.stringify(report, null, 2));
    console.log(`\n  Performance baseline written to ${outPath}`);
  });
});
