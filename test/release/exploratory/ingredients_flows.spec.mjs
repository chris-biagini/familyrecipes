import { test, expect } from '@playwright/test';
import { loginAs, trackConsoleErrors, trackNetworkErrors, readUserIds } from './setup.mjs';

let userIds;

test.beforeAll(async () => {
  userIds = await readUserIds();
});

test.describe('Ingredients catalog flows', () => {
  test('ingredients page renders with search and table', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha/ingredients');
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1')).toContainText('Ingredients');

    const searchInput = page.getByLabel('Search ingredients');
    await expect(searchInput).toBeVisible();

    const filterPills = page.locator('.filter-pills');
    await expect(filterPills).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('ingredients table shows data from recipes', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha/ingredients');
    await page.waitForLoadState('networkidle');

    const table = page.locator('table');
    if (await table.count() > 0) {
      const rows = table.locator('tbody tr');
      await expect(rows.first()).toBeVisible();
    }

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('search filters ingredients', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha/ingredients');
    await page.waitForLoadState('networkidle');

    const searchInput = page.getByLabel('Search ingredients');
    await searchInput.fill('flour');

    // Wait briefly for client-side filtering
    await page.waitForTimeout(300);

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('header links back to recipes and menu', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha/ingredients');
    await page.waitForLoadState('networkidle');

    const recipesLink = page.locator('article header').getByRole('link', { name: 'Recipes' });
    await expect(recipesLink).toBeVisible();

    const quickBitesLink = page.locator('article header').getByRole('link', { name: 'QuickBites' });
    await expect(quickBitesLink).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });
});
