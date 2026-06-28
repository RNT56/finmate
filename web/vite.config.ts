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
    environment: 'node',
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
  },
});
