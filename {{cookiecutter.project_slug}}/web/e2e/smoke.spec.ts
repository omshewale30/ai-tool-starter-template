import { expect, test } from "@playwright/test";

// Smoke test: the app loads and the dashboard renders. Runs with auth disabled
// (see playwright.config.ts webServer env), so no Entra config is needed.
test("dashboard loads", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Open assistant" })).toBeVisible();
});

test("local dev auth-disabled banner is shown", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByText(/Auth is disabled/i)).toBeVisible();
});
