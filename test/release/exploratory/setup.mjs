// Shared helpers for release exploratory tests.
// Assumes a running dev server on localhost:3030 with MULTI_KITCHEN=true.

import { expect } from '@playwright/test';

/**
 * Log in as a specific user by hitting the dev login endpoint.
 * @param {import('@playwright/test').Page} page
 * @param {number} userId
 */
export async function loginAs(page, userId) {
  await page.goto(`/dev_login?id=${userId}`);
  await page.waitForLoadState('networkidle');
}

/**
 * Attach a console error listener. Returns a function that asserts no errors.
 * @param {import('@playwright/test').Page} page
 * @returns {function} assertNoErrors — call at end of test
 */
export function trackConsoleErrors(page) {
  const errors = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      errors.push(msg.text());
    }
  });
  return () => {
    expect(errors, 'JS console errors detected').toEqual([]);
  };
}

/**
 * Attach a network failure listener for 4xx/5xx responses.
 * @param {import('@playwright/test').Page} page
 * @returns {function} assertNoNetworkErrors
 */
export function trackNetworkErrors(page) {
  const failures = [];
  page.on('response', (response) => {
    const status = response.status();
    if (status >= 400 && !response.url().includes('favicon')) {
      failures.push(`${status} ${response.url()}`);
    }
  });
  return () => {
    expect(failures, 'Network errors detected').toEqual([]);
  };
}

/**
 * Read the user IDs file written by the security seed script.
 */
export async function readUserIds() {
  const fs = await import('fs/promises');
  const path = await import('path');
  const idsPath = path.join(process.cwd(), 'test', 'security', 'user_ids.json');
  const content = await fs.readFile(idsPath, 'utf-8');
  return JSON.parse(content);
}
