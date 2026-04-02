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

    // Navigate to each page via Turbo Drive and verify content
    for (const [label, heading] of [['Menu', 'Menu'], ['Groceries', 'Groceries'], ['Ingredients', 'Ingredients']]) {
      await page.locator('nav').getByRole('link', { name: label }).first().click();
      await expect(page.locator('h1')).toContainText(heading);
    }

    await page.locator('nav').getByRole('link', { name: 'Recipes' }).first().click();
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

  test('mobile FAB renders on small viewport', async ({ browser }) => {
    // FAB requires touch device media queries: (pointer: coarse) and (hover: none)
    const context = await browser.newContext({
      viewport: { width: 375, height: 667 },
      hasTouch: true,
      isMobile: true,
    });
    const page = await context.newPage();

    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    const fabButton = page.locator('.fab-button');
    await expect(fabButton).toBeVisible();

    await fabButton.click();

    const fabPanel = page.locator('.fab-panel');
    await expect(fabPanel).toBeVisible();

    const fabNavLinks = fabPanel.locator('.fab-nav-links');
    await expect(fabNavLinks).toBeVisible();

    await page.keyboard.press('Escape');
    await expect(fabPanel).toBeHidden();

    assertNoConsoleErrors();
    assertNoNetworkErrors();

    await context.close();
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
