import { defineConfig } from '@playwright/test';

const port = Number(process.env.WP_PREVIEW_PORT || 4179);

export default defineConfig({
  testDir: './tests/browser',
  use: { baseURL: `http://127.0.0.1:${port}` },
  webServer: {
    command: `npm run preview -- --port ${port} --strictPort`,
    url: `http://127.0.0.1:${port}`,
    reuseExistingServer: false,
  },
});
