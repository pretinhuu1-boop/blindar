import { test, expect } from '@playwright/test';
test('login leva ao dashboard', async ({ page }) => {
  await page.goto('/login');
  await page.fill('[name=email]', 'a@b.c');
  await page.fill('[name=senha]', 'segredo');
  await page.click('button[type=submit]');
  await expect(page).toHaveURL(/dashboard/);
});
