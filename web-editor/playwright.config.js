import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/browser',
  use: { baseURL: 'http://127.0.0.1:4179' },
  webServer: {
    command: 'npm run preview -- --port 4179 --strictPort',
    url: 'http://127.0.0.1:4179',
    reuseExistingServer: !process.env.CI,
  },
});
