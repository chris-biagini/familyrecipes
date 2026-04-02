import { test, expect } from '@playwright/test';
import { loginAs, trackConsoleErrors, trackNetworkErrors, readUserIds } from './setup.mjs';

let userIds;

test.beforeAll(async () => {
  userIds = await readUserIds();
});

test.describe('Navigation flows', () => {
  test('main nav links are present and functional', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    for (const label of ['Recipes', 'Ingredients', 'Menu', 'Groceries']) {
      const link = page.locator('nav').getByRole('link', { name: label }).first();
      await expect(link).toBeVisible();
    }

    // Navigate to each page and verify it loads
    await page.locator('nav').getByRole('link', { name: 'Menu' }).first().click();
    await page.waitForLoadState('networkidle');
    await expect(page.locator('h1')).toContainText('Menu');

    await page.locator('nav').getByRole('link', { name: 'Groceries' }).first().click();
    await page.waitForLoadState('networkidle');
    await expect(page.locator('h1')).toContainText('Groceries');

    await page.locator('nav').getByRole('link', { name: 'Ingredients' }).first().click();
    await page.waitForLoadState('networkidle');
    await expect(page.locator('h1')).toContainText('Ingredients');

    await page.locator('nav').getByRole('link', { name: 'Recipes' }).first().click();
    await page.waitForLoadState('networkidle');
    await expect(page.locator('h1')).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('search overlay opens and closes', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    const searchButton = page.locator('nav').getByLabel('Search recipes');
    await expect(searchButton).toBeVisible();
    await searchButton.click();

    const searchDialog = page.locator('.search-overlay');
    await expect(searchDialog).toBeVisible();

    const searchInput = searchDialog.locator('.search-input');
    await expect(searchInput).toBeVisible();

    // Close with Escape
    await page.keyboard.press('Escape');
    await expect(searchDialog).toBeHidden();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('search overlay opens with / keyboard shortcut', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    await page.keyboard.press('/');

    const searchDialog = page.locator('.search-overlay');
    await expect(searchDialog).toBeVisible();

    await page.keyboard.press('Escape');
    await expect(searchDialog).toBeHidden();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('search overlay shows results for query', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    await page.keyboard.press('/');

    const searchInput = page.locator('.search-input');
    await searchInput.fill('test');

    const results = page.locator('.search-results');
    await expect(results).toBeVisible();

    await page.keyboard.press('Escape');

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('mobile FAB renders on small viewport', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await page.setViewportSize({ width: 375, height: 667 });

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    const fabButton = page.locator('.fab-button');
    await expect(fabButton).toBeVisible();

    await fabButton.click();

    const fabPanel = page.locator('.fab-panel');
    await expect(fabPanel).toBeVisible();

    // FAB panel should contain nav links
    const fabNavLinks = fabPanel.locator('.fab-nav-links');
    await expect(fabNavLinks).toBeVisible();

    // Close FAB
    await page.keyboard.press('Escape');
    await expect(fabPanel).toBeHidden();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('help link is present in nav', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    const helpLink = page.locator('nav').getByLabel('Help');
    await expect(helpLink).toBeVisible();

    const href = await helpLink.getAttribute('href');
    expect(href).toContain('/recipes/');

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });
});
