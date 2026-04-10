// Shared helpers for release exploratory tests.
// Assumes a running dev server on localhost:3030.

import { expect } from '@playwright/test';

/**
 * Log in as a specific user by hitting the dev login endpoint.
 * @param {import('@playwright/test').Page} page
 * @param {number} userId
 */
export async function loginAs(page, userId) {
  await page.goto(`/dev/login/${userId}`);
  await page.waitForLoadState('domcontentloaded');
}

/**
 * Attach a console error listener. Returns a function that asserts no errors.
 * Filters out known non-app noise: service worker registration failures,
 * favicon 404s, and similar browser-level messages.
 * @param {import('@playwright/test').Page} page
 * @returns {function} assertNoErrors — call at end of test
 */
const IGNORED_CONSOLE_PATTERNS = [
  /bad HTTP response code.*fetching the script/i,
  /service.worker/i,
  /favicon/i,
  /content security policy.*inline/i,
];

export function trackConsoleErrors(page) {
  const errors = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      const text = msg.text();
      if (!IGNORED_CONSOLE_PATTERNS.some(p => p.test(text))) {
        errors.push(text);
      }
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
