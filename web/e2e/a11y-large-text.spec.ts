import { test, expect, type Page } from '@playwright/test';

// Dynamic-Type / zoom accessibility proof (docs/06 §accessibility, docs/10
// M7-A11Y-01). The web mirror of the iOS "largest accessibility sizes" pass:
// we crank the document root font to 200% (≈32px) BEFORE the app boots, drive
// the offline demo path, then assert that every key route lays out WITHOUT
// horizontal overflow and still shows its heading. A layout that only works at
// the default 16px root font fails here.
//
// Why root-font and not browser zoom: CSS `rem`/`em` are relative to the root
// font, so scaling document.documentElement.fontSize is the deterministic,
// headless-friendly analogue of a user bumping their OS/browser text size — and
// it is exactly what a non-scaling fixed-px layout breaks under.

const LARGE_ROOT_FONT = '200%';

// Inject the large root font as the very first thing on every document, so the
// first paint already reflects it (no flash of default-size layout). Must run
// per-page via addInitScript registered in beforeEach.
test.beforeEach(async ({ page }) => {
  // Set the root font as early as the document allows. At document-start the
  // <html> element may not exist yet, so apply it immediately if present AND
  // again on DOMContentLoaded — whichever fires first wins, and the second is a
  // no-op. This survives the reload below because addInitScript re-runs on every
  // navigation in this context.
  await page.addInitScript((size) => {
    const apply = () => {
      document.documentElement.style.fontSize = size as string;
    };
    if (document.documentElement) apply();
    document.addEventListener('DOMContentLoaded', apply, { once: true });
  }, LARGE_ROOT_FONT);

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

/**
 * Assert the document has no horizontal overflow. A few CSS subpixel rounding
 * artifacts are normal, so allow a small tolerance — anything larger means real
 * content is forcing a horizontal scrollbar.
 */
async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const { scrollWidth, clientWidth } = await page.evaluate(() => {
    const el = document.documentElement;
    return { scrollWidth: el.scrollWidth, clientWidth: el.clientWidth };
  });
  expect(
    scrollWidth,
    `horizontal overflow: scrollWidth ${scrollWidth} > clientWidth ${clientWidth}`
  ).toBeLessThanOrEqual(clientWidth + 2);
}

test('confirms the 200% root font actually took effect', async ({ page }) => {
  await enterAppViaDemo(page);
  const fontPx = await page.evaluate(() =>
    parseFloat(getComputedStyle(document.documentElement).fontSize)
  );
  // 200% of the 16px default ≈ 32px; assert it is clearly enlarged.
  expect(fontPx).toBeGreaterThanOrEqual(28);
});

test('no horizontal overflow at 200% root font across key routes', async ({
  page,
}) => {
  await enterAppViaDemo(page);

  // Home (index) — first paint already at the large font.
  await expect(
    page.getByRole('heading', { level: 1, name: 'Home' })
  ).toBeVisible();
  await expectNoHorizontalOverflow(page);

  // Subscriptions.
  await page.getByTestId('nav-subscriptions').click();
  await expect(
    page.getByRole('heading', { level: 1, name: 'Subscriptions' })
  ).toBeVisible();
  await expectNoHorizontalOverflow(page);

  // Cash Flow — KPI grid, money-flow SVG, breakdown table.
  await page.getByTestId('nav-cash-flow').click();
  await expect(
    page.getByRole('heading', { level: 1, name: 'Cash Flow' })
  ).toBeVisible();
  await expectNoHorizontalOverflow(page);

  // More hub.
  await page.getByTestId('nav-more').click();
  await expect(
    page.getByRole('heading', { level: 1, name: 'More' })
  ).toBeVisible();
  await expectNoHorizontalOverflow(page);

  // Calendar — 7-column month grid is a classic overflow offender.
  await page.getByTestId('nav-calendar').click();
  await expect(
    page.getByRole('heading', { level: 1, name: 'Calendar' })
  ).toBeVisible();
  await expectNoHorizontalOverflow(page);
});

test('Settings (deep route under More) has no overflow at 200% root font', async ({
  page,
}) => {
  await enterAppViaDemo(page);

  // Navigate in-app (the demo session is in-memory React state, so a full-page
  // goto would drop it back to Login). More → Settings via the link.
  await page.getByTestId('nav-more').click();
  await page.getByRole('link', { name: 'Settings' }).click();
  await expect(page).toHaveURL(/\/settings$/);
  await expect(
    page.getByRole('heading', { level: 1, name: 'Settings' })
  ).toBeVisible();
  await expectNoHorizontalOverflow(page);
});
