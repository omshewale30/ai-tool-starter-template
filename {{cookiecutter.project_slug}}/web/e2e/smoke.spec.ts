import { expect, test } from "@playwright/test";

test("home page renders inside the app shell", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("navigation", { name: "Primary" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Open assistant" })).toBeVisible();
  await expect(page.getByText(/Sign-in is disabled for local development/)).toBeVisible();
});

test("the web app forwards /api/health to the API", async ({ request }) => {
  const response = await request.get("/api/health");
  expect(response.ok()).toBeTruthy();
  const body = await response.json();
  expect(body).toMatchObject({ status: "ok", database: "ok", ai: { provider: "mock" } });
});

test("profile loads the caller from the API", async ({ page }) => {
  await page.goto("/profile");
  await expect(page.getByText("dev@localhost")).toBeVisible();
});

test("assistant answers through the proxy", async ({ page }) => {
  await page.goto("/chat");
  await page.getByLabel("Message").fill("Hello there");
  await page.getByRole("button", { name: "Send" }).click();
  // The mock provider echoes the prompt back.
  await expect(page.getByText("[mock] You said: Hello there")).toBeVisible();
  // Next.js renders its own role=alert route announcer, so match our error box by text.
  await expect(page.getByRole("alert").filter({ hasText: "Error" })).toHaveCount(0);
});
