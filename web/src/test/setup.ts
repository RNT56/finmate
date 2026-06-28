// Vitest setup — shared across all test files. Unmounts any React trees rendered by
// @testing-library/react after each test so no render work is left queued on the
// scheduler when the (jsdom) environment tears down. Harmless for the node-environment
// pure-core tests, which never render anything.
import { afterEach } from 'vitest';

afterEach(async () => {
  // Import lazily so the node-environment core tests don't pull in jsdom-only deps.
  try {
    const { cleanup } = await import('@testing-library/react');
    cleanup();
  } catch {
    // @testing-library/react unavailable (e.g. pure-node test run) — nothing to clean.
  }
});
