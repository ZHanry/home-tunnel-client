import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests/browser", timeout: 20_000, workers: 1,
  use: { baseURL: "http://127.0.0.1:4176", locale: "zh-CN", viewport: { width: 1440, height: 960 }, trace: "retain-on-failure" },
});
