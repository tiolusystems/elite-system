import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  outputDir: "../../artifacts/e2e/test-results",
  timeout: 45_000,
  retries: 1,
  reporter: [["list"], ["html", { outputFolder: "../../artifacts/e2e/report", open: "never" }]],
  use: {
    baseURL: process.env.E2E_BASE_URL || "http://127.0.0.1:3100",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "retain-on-failure"
  },
  projects: [
    { name: "desktop-1920", use: { viewport: { width: 1920, height: 1080 } } },
    { name: "desktop-1366", use: { viewport: { width: 1366, height: 768 } } },
    { name: "tablet-768", use: { viewport: { width: 768, height: 1024 } } },
    { name: "mobile-390", use: { viewport: { width: 390, height: 844 } } },
    { name: "mobile-360", use: { viewport: { width: 360, height: 800 } } }
  ]
});
