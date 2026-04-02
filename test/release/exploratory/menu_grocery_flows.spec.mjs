import { test, expect } from '@playwright/test';
import { loginAs, trackConsoleErrors, trackNetworkErrors, readUserIds } from './setup.mjs';

let userIds;

test.beforeAll(async () => {
  userIds = await readUserIds();
});

test.describe('Menu and grocery flows', () => {
  test('menu page renders with header and recipe selector', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha/menu');
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1')).toContainText('Menu');

    const groceriesLink = page.getByRole('link', { name: 'Groceries' });
    await expect(groceriesLink.first()).toBeVisible();

    const menuApp = page.locator('#menu-app');
    await expect(menuApp).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('dinner picker button is visible when recipes exist', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha/menu');
    await page.waitForLoadState('networkidle');

    const pickerButton = page.locator('#dinner-picker-button');
    if (await pickerButton.count() > 0) {
      await expect(pickerButton).toBeVisible();
      await expect(pickerButton).toContainText('What Should We Make');
    }

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('groceries page renders shopping list structure', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha/groceries');
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1')).toContainText('Groceries');

    const menuLink = page.getByRole('link', { name: 'Menu' });
    await expect(menuLink.first()).toBeVisible();

    const shoppingList = page.locator('#shopping-list');
    await expect(shoppingList).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('navigate from menu to groceries via link', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha/menu');
    await page.waitForLoadState('networkidle');

    const groceriesLink = page.locator('#menu-header').getByRole('link', { name: 'Groceries' });
    await groceriesLink.click();
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1')).toContainText('Groceries');

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });
});
