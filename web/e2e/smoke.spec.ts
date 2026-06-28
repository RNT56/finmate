import { test, expect, type Page } from '@playwright/test';

// Critical-flow smoke suite (docs/09) — the web mirror of App/UITests/
// FinmateUITests.swift. Black-box tests driving the real built app through the
// fully offline "Try the demo" path: no network, deterministic in-memory sample
// data, so the Login → onboarding → app-shell flow is reproducible across runs.
//
// Stable hooks (non-visual data-testid, added in the app):
//   try-demo · onboarding-continue · add-subscription ·
//   subscription-name / -amount / -save · nav-{home,subscriptions,…}

// Clear localStorage before each test so the first-run guard always shows
// onboarding (the demo user is in-memory; only the onboarded flag persists).
// We must clear AFTER the origin loads — localStorage is origin-scoped — so we
// navigate to "/", clear, then reload into a guaranteed clean first-run state.
test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => window.localStorage.clear());
  await page.reload();
});

/** Drive the offline demo path: "Try the demo" → onboarding "Get started" →
 *  land in the app shell. Asserts each step is reached. */
async function enterAppViaDemo(page: Page): Promise<void> {
  await expect(page.getByTestId('try-demo')).toBeVisible();
  await page.getByTestId('try-demo').click();

  const getStarted = page.getByTestId('onboarding-continue');
  await expect(getStarted).toBeVisible();
  await getStarted.click();

  // The app shell is shown once the primary nav exists.
  await expect(page.getByRole('navigation', { name: 'Primary' })).toBeVisible();
}

test('launch → demo → onboarding → app shell / Home is shown', async ({
  page,
}) => {
  await enterAppViaDemo(page);

  // Home is the index route — its page title + a nav link to itself.
  await expect(
    page.getByRole('heading', { level: 1, name: 'Home' })
  ).toBeVisible();
  await expect(page.getByTestId('nav-home')).toBeVisible();
  await expect(page.getByTestId('nav-subscriptions')).toBeVisible();
});

test('navigates to each primary section and renders its heading', async ({
  page,
}) => {
  await enterAppViaDemo(page);

  await page.getByTestId('nav-subscriptions').click();
  await expect(page).toHaveURL(/\/subscriptions$/);
  await expect(
    page.getByRole('heading', { level: 1, name: 'Subscriptions' })
  ).toBeVisible();

  await page.getByTestId('nav-cash-flow').click();
  await expect(page).toHaveURL(/\/cash-flow$/);
  await expect(
    page.getByRole('heading', { level: 1, name: 'Cash Flow' })
  ).toBeVisible();

  await page.getByTestId('nav-calendar').click();
  await expect(page).toHaveURL(/\/calendar$/);
  await expect(
    page.getByRole('heading', { level: 1, name: 'Calendar' })
  ).toBeVisible();

  await page.getByTestId('nav-more').click();
  await expect(page).toHaveURL(/\/more$/);
  await expect(
    page.getByRole('heading', { level: 1, name: 'More' })
  ).toBeVisible();

  await page.getByTestId('nav-home').click();
  await expect(page).toHaveURL(/\/$/);
  await expect(
    page.getByRole('heading', { level: 1, name: 'Home' })
  ).toBeVisible();
});

test('adds a subscription and the new row appears in the list', async ({
  page,
}) => {
  await enterAppViaDemo(page);

  await page.getByTestId('nav-subscriptions').click();
  await expect(
    page.getByRole('heading', { level: 1, name: 'Subscriptions' })
  ).toBeVisible();

  // Open the add form.
  await page.getByTestId('add-subscription').click();
  const dialog = page.getByRole('dialog', { name: 'Add subscription' });
  await expect(dialog).toBeVisible();

  // Fill name + amount and save.
  const uniqueName = `E2ESub ${Date.now()}`;
  await page.getByTestId('subscription-name').fill(uniqueName);
  await page.getByTestId('subscription-amount').fill('9.99');
  await page.getByTestId('subscription-save').click();

  // The dialog closes and the new row appears in the list.
  await expect(dialog).toBeHidden();
  await expect(page.getByText(uniqueName)).toBeVisible();
});
