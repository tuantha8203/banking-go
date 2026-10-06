import { defineConfig, devices } from '@playwright/test'

const port = 4174

// Smoke e2e against the production build served by `vite preview` (run `pnpm build` first; `make e2e` does).
export default defineConfig({
  testDir: './e2e',
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: { baseURL: `http://localhost:${port}`, trace: 'on-first-retry' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'pnpm preview',
    url: `http://localhost:${port}`,
    reuseExistingServer: !process.env.CI,
  },
})
