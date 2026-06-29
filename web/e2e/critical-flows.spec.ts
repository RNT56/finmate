import { test, expect, type Page } from '@playwright/test';

// Extra critical-flow E2E coverage (docs/09, docs/10 M8-TEST-01), complementing
// smoke.spec.ts. Both flows run on the deterministic offline demo path (no
// network, in-memory sample data):
//   1. CSV import — paste a tiny subscriptions CSV → map → preview → import →
//      the new row shows up on the Subscriptions list.
//   2. Currency switch — Settings → change the default display currency to USD →
//      a Cash Flow amount renders with the USD symbol.

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => window.localStorage.clear());
  await page.reload();
});

/** Drive the offline demo path into the app shell (same hooks as smoke). */
async function enterAppViaDemo(page: Page): Promise<void> {
  await expect(page.getByTestId('try-demo')).toBeVisible();
  await page.getByTestId('try-demo').click();

  const getStarted = page.getByTestId('onboarding-continue');
  await expect(getStarted).toBeVisible();
  await getStarted.click();

  await expect(page.getByRole('navigation', { name: 'Primary' })).toBeVisible();
}

test('CSV import: paste → map → preview → import → row appears in Subscriptions', async ({
  page,
}) => {
  await enterAppViaDemo(page);

  // More → Import CSV.
  await page.getByTestId('nav-more').click();
  await page.getByRole('link', { name: 'Import CSV' }).click();
  await expect(page).toHaveURL(/\/import$/);
  await expect(
    page.getByRole('heading', { level: 1, name: 'Import CSV' })
  ).toBeVisible();

  // Paste a minimal, header-aliased subscriptions CSV with a unique name so the
  // assertion can't collide with the demo sample data.
  const uniqueName = `CsvImported ${Date.now()}`;
  const csv = `name,amount,currency,billing_period\n${uniqueName},4.50,EUR,monthly`;
  await page.getByLabel('CSV text').fill(csv);

  // Header aliases (name/amount/currency/billing_period) auto-map, so we can go
  // straight to mapping → preview.
  await page.getByRole('button', { name: 'Map columns' }).click();

  // The mapping card renders; required fields (Name, Amount) auto-resolve.
  await page.getByRole('button', { name: 'Preview rows' }).click();

  // Preview shows our row before any write. Scope to the preview table cell so
  // we don't also match the still-populated CSV textarea (strict-mode).
  await expect(
    page.getByRole('cell', { name: uniqueName })
  ).toBeVisible();

  // Import the valid row(s).
  await page.getByRole('button', { name: /^Import \d+ valid$/ }).click();

  // Confirmation + jump to Subscriptions.
  await expect(page.getByText(/Imported 1 subscription/)).toBeVisible();
  await page.getByRole('button', { name: 'View subscriptions' }).click();

  await expect(page).toHaveURL(/\/subscriptions$/);
  await expect(page.getByText(uniqueName)).toBeVisible();
});

test('currency switch: Settings → USD → a Cash Flow amount uses the $ symbol', async ({
  page,
}) => {
  await enterAppViaDemo(page);

  // Cash Flow first, at the default currency (EUR → € amounts).
  await page.getByTestId('nav-cash-flow').click();
  await expect(
    page.getByRole('heading', { level: 1, name: 'Cash Flow' })
  ).toBeVisible();
  // Sanity: at least one Euro amount is on screen before the switch.
  await expect(page.getByText(/€/).first()).toBeVisible();

  // Settings → Default display currency → USD.
  await page.getByTestId('nav-more').click();
  await page.getByRole('link', { name: 'Settings' }).click();
  await expect(page).toHaveURL(/\/settings$/);

  const currencyGroup = page.getByRole('group', {
    name: 'Default display currency',
  });
  await currencyGroup.getByRole('button', { name: 'USD' }).click();
  // The control reflects the new selection.
  await expect(
    currencyGroup.getByRole('button', { name: 'USD' })
  ).toHaveAttribute('aria-pressed', 'true');

  // Back to Cash Flow — amounts now render with the USD symbol.
  await page.getByTestId('nav-cash-flow').click();
  await expect(
    page.getByRole('heading', { level: 1, name: 'Cash Flow' })
  ).toBeVisible();
  await expect(page.getByText(/\$/).first()).toBeVisible();
});
