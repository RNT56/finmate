// First-run onboarding completion flag (docs/02 §2). Persisted per-browser so a
// returning user skips onboarding. Demo and live users share the same gate; the
// app reads it through this tiny module rather than touching storage directly.

const STORAGE_KEY = 'finmate.onboarded.v1';

export function isOnboarded(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'true';
  } catch {
    return false;
  }
}

export function setOnboarded(value: boolean): void {
  try {
    if (value) localStorage.setItem(STORAGE_KEY, 'true');
    else localStorage.removeItem(STORAGE_KEY);
  } catch {
    // localStorage unavailable (private mode) — best effort only.
  }
}
