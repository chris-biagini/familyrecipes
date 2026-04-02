import { test, expect } from '@playwright/test';
import { loginAs, trackConsoleErrors, trackNetworkErrors, readUserIds } from './setup.mjs';

let userIds;

test.beforeAll(async () => {
  userIds = await readUserIds();
});

test.describe('Recipe flows', () => {
  test('homepage renders recipe listings', async ({ page }) => {
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

  test('recipe show page renders content', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');

    const firstRecipeLink = page.locator('.recipe-card-title').first();
    const recipeName = await firstRecipeLink.textContent();
    await firstRecipeLink.click();
    await page.waitForLoadState('networkidle');

    await expect(page.locator('h1')).toContainText(recipeName.trim());

    const steps = page.locator('section');
    await expect(steps.first()).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('edit button opens recipe editor dialog', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');

    await page.locator('.recipe-card-title').first().click();
    await page.waitForLoadState('networkidle');

    const editButton = page.locator('#edit-button');
    await expect(editButton).toBeVisible();
    await editButton.click();

    const editorDialog = page.locator('#recipe-editor');
    await expect(editorDialog).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });

  test('new recipe button opens editor on homepage', async ({ page }) => {
    const assertNoConsoleErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userIds.alice_id);
    await page.goto('/kitchens/kitchen-alpha');

    const newButton = page.locator('#new-recipe-button');
    await expect(newButton).toBeVisible();
    await newButton.click();

    const editorDialog = page.locator('#recipe-editor');
    await expect(editorDialog).toBeVisible();

    assertNoConsoleErrors();
    assertNoNetworkErrors();
  });
});
