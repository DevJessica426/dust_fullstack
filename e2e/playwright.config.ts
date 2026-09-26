import { defineConfig } from '@playwright/test';
import { baseConfig } from './specs/playwright.base';

/**
 * The RealWorld suite's own base config, pointed at this server.
 *
 * `tool/e2e.sh` starts the server, seeds it, and sets BASE_URL, API_BASE and
 * TEST_MODE=spa (the browser holds the JWT and calls the API itself, which is
 * what this app does). Retries are off: a flaky test should show up as one.
 */
export default defineConfig({
  ...baseConfig,
  testDir: './specs',
  retries: 0,
  reporter: [['list'], ['json', { outputFile: 'test-results/results.json' }]],
  use: {
    ...baseConfig.use,
    baseURL: process.env.BASE_URL ?? 'http://localhost:8090',
  },
});
