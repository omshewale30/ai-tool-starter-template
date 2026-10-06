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
  await expect(page.getByText("[mock] You said: Hello there", { exact: true })).toBeVisible();
  // Next.js renders its own role=alert route announcer, so match our error box by text.
  await expect(page.getByRole("alert").filter({ hasText: "Error" })).toHaveCount(0);
});

test("streamed answers arrive through the proxy as server-sent events", async ({ request }) => {
  const response = await request.post("/api/v1/chat/stream", {
    data: { message: "stream please" },
  });
  expect(response.ok()).toBeTruthy();
  expect(response.headers()["content-type"]).toContain("text/event-stream");
  const body = await response.text();
  expect(body).toContain("event: delta");
  expect(body.trim().split("\n\n").at(-1)).toContain("event: done");
});

test("admins see AI usage in the activity log", async ({ page, request }) => {
  await request.post("/api/v1/chat", { data: { message: "log me" } });
  await page.goto("/admin");
  await expect(page.getByRole("table", { name: "Recent audit events" })).toBeVisible();
  await expect(page.getByRole("cell", { name: "chat.completed" }).first()).toBeVisible();
  await expect(page.getByText(/mock-1 · \d+ in \/ \d+ out/).first()).toBeVisible();
});
