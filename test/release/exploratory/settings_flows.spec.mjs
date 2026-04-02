import { test, expect } from '@playwright/test';
import { loginAs, trackConsoleErrors, trackNetworkErrors, readUserIds } from './setup.mjs';

let userIds;

test.beforeAll(async () => {
  userIds = await readUserIds();
});

test.describe('Settings and dinner picker flows', () => {
  test('settings button opens settings dialog', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    const settingsButton = page.locator('#settings-button');
    await expect(settingsButton).toBeVisible();
    await settingsButton.click();

    const settingsDialog = page.locator('#settings-editor');
    await expect(settingsDialog).toBeVisible();

    const settingsFrame = page.locator('#settings-editor-frame');
    await expect(settingsFrame).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('settings dialog loads editor frame content', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    await page.locator('#settings-button').click();

    const settingsDialog = page.locator('#settings-editor');
    await expect(settingsDialog).toBeVisible();

    // Wait for turbo frame to load (placeholder should disappear)
    await expect(page.locator('#settings-editor-frame .loading-placeholder')).toBeHidden({ timeout: 5000 });

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('dinner picker opens from menu page', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha/menu');
    await page.waitForLoadState('networkidle');

    const pickerButton = page.locator('#dinner-picker-button');
    if (await pickerButton.count() > 0) {
      await pickerButton.click();

      const pickerDialog = page.locator('#dinner-picker-dialog');
      await expect(pickerDialog).toBeVisible();

      await expect(page.locator('.dinner-picker-heading')).toContainText("What's for Dinner");

      const spinButton = page.locator('.dinner-picker-spin-btn');
      await expect(spinButton).toBeVisible();
    }

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('category order editor opens from homepage', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    const editCategoriesButton = page.locator('#edit-categories-button');
    if (await editCategoriesButton.count() > 0) {
      await editCategoriesButton.click();

      const dialog = page.locator('#category-order-editor');
      await expect(dialog).toBeVisible();
    }

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });
});
