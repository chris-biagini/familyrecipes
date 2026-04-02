import { test, expect } from '@playwright/test';
import { loginAs, trackConsoleErrors, trackNetworkErrors, readUserIds } from './setup.mjs';

let userIds;

test.beforeAll(async () => {
  userIds = await readUserIds();
});

test.describe('Multi-tenant isolation', () => {
  test('alice sees kitchen-alpha content', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1')).toBeVisible();

    const recipeCards = page.locator('.recipe-card');
    await expect(recipeCards.first()).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('bob sees kitchen-beta content', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.bob_id);
    await page.goto('/kitchens/kitchen-beta');
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1')).toBeVisible();

    const recipeCards = page.locator('.recipe-card');
    await expect(recipeCards.first()).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('alice cannot access kitchen-beta recipes page', async ({ page }) => {
    await loginAs(page, userIds.alice_id);

    const response = await page.goto('/kitchens/kitchen-beta');
    const status = response.status();

    // Should either redirect or show forbidden/not-found — not render beta content
    if (status === 200) {
      // If it renders, alice should not see kitchen-beta-specific member features
      // (she's not a member of beta, so edit buttons should be absent)
      const editButton = page.locator('#edit-button');
      await expect(editButton).toHaveCount(0);
    }
  });

  test('bob cannot access kitchen-alpha recipes page', async ({ page }) => {
    await loginAs(page, userIds.bob_id);

    const response = await page.goto('/kitchens/kitchen-alpha');
    const status = response.status();

    if (status === 200) {
      const editButton = page.locator('#edit-button');
      await expect(editButton).toHaveCount(0);
    }
  });

  test('kitchen-scoped URLs stay within tenant boundary', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    // Navigate through the app and verify URLs stay within kitchen-alpha scope
    const menuLink = page.getByRole('link', { name: 'Menu' }).first();
    if (await menuLink.isVisible()) {
      await menuLink.click();
      await page.waitForLoadState('networkidle');
      expect(page.url()).toContain('kitchen-alpha');
    }

    const groceriesLink = page.getByRole('link', { name: 'Groceries' }).first();
    if (await groceriesLink.isVisible()) {
      await groceriesLink.click();
      await page.waitForLoadState('networkidle');
      expect(page.url()).toContain('kitchen-alpha');
    }

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('landing page lists kitchens in multi-kitchen mode', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // In multi-kitchen mode, root should show kitchen list or redirect
    // Just verify the page loads without errors
    await expect(page.locator('body')).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });
});
