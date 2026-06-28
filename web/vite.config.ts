import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// https://vite.dev/config/ — vitest/config re-exports Vite's defineConfig with the
// `test` field typed.
export default defineConfig({
  plugins: [react()],
  // Honor the PORT env (e.g. assigned by preview tooling / hosts); fall back to Vite's default.
  server: { port: process.env.PORT ? Number(process.env.PORT) : 5173, host: true },
  preview: { port: process.env.PORT ? Number(process.env.PORT) : 4173 },
  test: {
    globals: false,
    // Default to the fast node environment for the pure-core suites; hook/component
    // test files opt into jsdom with a `// @vitest-environment jsdom` file directive.
    environment: 'node',
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
    // Playwright E2E specs live under e2e/ and use a different runner; keep them
    // out of Vitest entirely (the include above already scopes to src/, this is
    // belt-and-suspenders so the two suites never collide).
    exclude: ['node_modules/**', 'dist/**', 'e2e/**'],
    setupFiles: ['src/test/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'text-summary'],
      // Measure the logic layers we actually unit-test: the shared algorithm core and
      // the store/hook layer. The Supabase repositories, view components, and entry
      // points are integration-tested elsewhere (or require a live backend) and would
      // make a line gate flaky, so they are excluded from the threshold.
      include: [
        'src/core/**/*.ts',
        'src/features/**/use*.ts',
        'src/features/**/use*.tsx',
        'src/features/**/types.ts',
        'src/features/**/repository.ts',
        'src/features/**/entityForm.ts',
        'src/features/**/assetForm.ts',
        'src/features/**/onboardingState.ts',
        'src/lib/authRoute.ts',
        'src/lib/rates.ts',
      ],
      // Conservative, non-flaky floor — comfortably below current coverage so the gate
      // catches regressions without breaking on small, well-tested changes.
      thresholds: {
        lines: 70,
        functions: 70,
        statements: 70,
        branches: 70,
      },
    },
  },
});
