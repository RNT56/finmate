import { defineConfig, devices } from '@playwright/test';

// Playwright E2E config (docs/09 — critical-flow smoke, web mirror of the iOS
// XCUITest suite). Drives the fully offline "Try the demo" path against the
// built+previewed app: deterministic, no network, no Supabase configured.
//
// Specs live under e2e/ (NOT src/) so the Vitest suite (src/**/*.test.ts(x))
// and Playwright never collide — vite.config.ts also excludes e2e/ explicitly.

const PORT = Number(process.env.PORT ?? 4173);
const baseURL = `http://localhost:${PORT}`;

export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.spec.ts',
  // Fail fast on a stray `test.only` left in a committed spec.
  forbidOnly: !!process.env.CI,
  // The demo path is deterministic — no retries needed, but allow one on CI to
  // absorb a rare cold-start hiccup without masking real flakiness locally.
  retries: process.env.CI ? 1 : 0,
  // Run serially in one worker so the shared preview server stays predictable.
  workers: 1,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  timeout: 30_000,
  expect: { timeout: 10_000 },
  use: {
    baseURL,
    headless: true,
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // Build then preview the production bundle on a fixed port. Reuse an already
  // running server locally for fast iteration; always start fresh on CI.
  webServer: {
    command: `npm run build && npm run preview -- --port ${PORT}`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
