import { defineConfig, devices } from "@playwright/test";

/*
 * End-to-end smoke tests against the real stack: the FastAPI app (mock AI,
 * auth disabled, a throwaway SQLite file) and a production build of the web
 * app, which forwards /api/* to it exactly as in Azure.
 *
 * Needs the API's Python dependencies installed. Set PYTHON to choose the
 * interpreter (defaults to the repo's .venv when present).
 */
const python =
  process.env.PYTHON ?? (process.env.VIRTUAL_ENV ? "python" : "../.venv/bin/python");

export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: "http://127.0.0.1:3000",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: [
    {
      command: `${python} -m alembic upgrade head && ${python} -m uvicorn app.main:app --port 8000`,
      cwd: "../api",
      url: "http://127.0.0.1:8000/health/live",
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
      env: {
        ENVIRONMENT: "test",
        AUTH_MODE: "disabled",
        AI_PROVIDER: "mock",
        DATABASE_URL: "sqlite+pysqlite:///./e2e.db",
      },
    },
    {
      command: "npm run build && npm run start -- --port 3000",
      url: "http://127.0.0.1:3000",
      reuseExistingServer: !process.env.CI,
      timeout: 180_000,
      env: {
        // Build-time: the only way to switch sign-in off (see AuthProvider).
        NEXT_PUBLIC_AUTH_DISABLED: "true",
        BACKEND_ORIGIN: "http://127.0.0.1:8000",
      },
    },
  ],
});
