import { defineConfig } from '@playwright/test';

// Watchable run of the whole browser suite: visible Chromium, one worker, slowed input.
// Usage: npm run test:showcase   (SHOWCASE_SLOWMO_MS, WP_PREVIEW_PORT optional)
const port = Number(process.env.WP_PREVIEW_PORT || 43700);

export default defineConfig({
  testDir: './tests/browser',
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    headless: false,
    launchOptions: { slowMo: Number(process.env.SHOWCASE_SLOWMO_MS ?? 250) },
    trace: 'off',
  },
  webServer: {
    command: `npm run preview -- --port ${port} --strictPort`,
    url: `http://127.0.0.1:${port}`,
    reuseExistingServer: false,
  },
});
