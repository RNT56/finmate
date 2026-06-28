import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';
import prettier from 'eslint-config-prettier';
import globals from 'globals';

// Finmate web — flat ESLint config (ESLint 9).
// @typescript-eslint + react-hooks recommended, Prettier last to disable
// stylistic rules (formatting is owned by Prettier, see .prettierrc).
export default tseslint.config(
  // Never lint build output, deps, generated caches, or E2E run artifacts.
  {
    ignores: [
      'dist/**',
      'node_modules/**',
      'coverage/**',
      '*.tsbuildinfo',
      'test-results/**',
      'playwright-report/**',
      'blob-report/**',
    ],
  },

  // Base JS + TypeScript recommended rule sets.
  js.configs.recommended,
  ...tseslint.configs.recommended,

  // React + browser source.
  {
    files: ['src/**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...globals.browser },
    },
    plugins: {
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react-refresh/only-export-components': [
        'warn',
        { allowConstantExport: true },
      ],
      // Allow intentionally-unused args/vars when prefixed with `_`.
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],
    },
  },

  // Node-context config/build files (vite.config, eslint.config, playwright.config).
  {
    files: ['*.{js,ts}', 'vite.config.ts'],
    languageOptions: {
      globals: { ...globals.node },
    },
  },

  // Playwright E2E specs — run outside src/ by the Playwright runner. They use
  // Node globals (process.env) and, inside page.evaluate closures, browser
  // globals (window). Not part of any tsconfig build, so tsc -b ignores them.
  {
    files: ['e2e/**/*.ts'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...globals.node, ...globals.browser },
    },
  },

  // Hook/provider colocation files (e.g. usePreferences.tsx export both a
  // Provider component and its companion hook) — the react-refresh
  // "only-export-components" hint is a false positive for this idiomatic pattern.
  {
    files: ['src/**/use*.tsx'],
    rules: {
      'react-refresh/only-export-components': 'off',
    },
  },

  // Test files: relax a few rules that are noise in test fixtures.
  {
    files: ['src/**/*.test.{ts,tsx}'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },

  // Keep Prettier last so it wins any formatting-rule conflicts.
  prettier
);
