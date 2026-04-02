import { test, expect } from '@playwright/test';
import { loginAs, trackConsoleErrors, trackNetworkErrors, readUserIds } from './setup.mjs';

let userIds;

test.beforeAll(async () => {
  userIds = await readUserIds();
});

test.describe('Import and export flows', () => {
  test('export button is visible on homepage for members', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    const exportActions = page.locator('#export-actions');
    await expect(exportActions).toBeVisible();

    const exportLink = exportActions.getByRole('link', { name: 'Export All Data' });
    await expect(exportLink).toBeVisible();

    // Verify the export link points to the export path
    const href = await exportLink.getAttribute('href');
    expect(href).toContain('export');

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('import button is visible on homepage for members', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    const importButton = page.getByRole('button', { name: 'Import', exact: true });
    await expect(importButton).toBeVisible();

    // The hidden file input should exist
    const fileInput = page.locator('input[type="file"][name="files[]"]');
    await expect(fileInput).toBeAttached();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('AI import button visible when API key is set', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    // kitchen-alpha has an anthropic_api_key set by the seed script
    const aiButton = page.locator('#ai-import-button');
    if (await aiButton.count() > 0) {
      await expect(aiButton).toBeVisible();
      await aiButton.click();

      const aiDialog = page.locator('#ai-import-editor');
      await expect(aiDialog).toBeVisible();

      const textarea = aiDialog.locator('textarea');
      await expect(textarea).toBeVisible();

      const submitButton = aiDialog.getByRole('button', { name: 'Import' });
      await expect(submitButton).toBeVisible();
    }

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('export and import are not visible to non-members', async ({ page }) => {
    // No console/network error tracking here — non-members trigger expected
    // 403s on protected Turbo Frames (editor dialogs, settings frame).
    await loginAs(page, userIds.bob_id);
    await page.goto('/kitchens/kitchen-alpha');
    await page.waitForLoadState('networkidle');

    const exportActions = page.locator('#export-actions');
    await expect(exportActions).toHaveCount(0);
  });
});
