import { readFile } from "node:fs/promises";
import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  const root = new URL("../../internal/gui/web/", import.meta.url);
  await page.route("**/desktop-preview", async (route) =>
    route.fulfill({
      contentType: "text/html",
      body: await readFile(new URL("index.html", root), "utf8"),
    }),
  );
  await page.route("**/desktop.js", async (route) =>
    route.fulfill({
      contentType: "text/javascript",
      body: await readFile(new URL("desktop.js", root), "utf8"),
    }),
  );
  await page.route("**/local/state", (route) => route.fulfill({ json: { enrolled: false } }));
  await page.goto("/desktop-preview");
});

test("desktop requests use the native window's private session", async ({ page }) => {
  await page.goto("about:blank");
  let authorization = "";
  await page.route("**/local/state", (route) => {
    authorization = route.request().headers().authorization ?? "";
    return route.fulfill({ json: { enrolled: false } });
  });
  await page.goto("/desktop-preview#session=private-ui-test");
  await expect.poll(() => authorization).toBe("Bearer private-ui-test");
});

async function services(page, capabilities, connections = []) {
  await page.route("**/local/state", route => route.fulfill({json:{enrolled:true,agent_state:"Online",capabilities,connections}}));
  await page.route("**/local/update", route => route.fulfill({json:{newer:false}}));
  await page.reload();
  await expect(page.locator("#home")).toBeVisible();
}

test("RTSP preset creates TCP with an automatic port and no required web subdomain", async ({page}) => {
  await services(page,{supported:true,tcp:{enabled:true,can_create:true},udp:{enabled:true,can_create:true}});
  await page.route("**/local/connections", route => route.fulfill({json:{id:"camera"}}));
  await page.locator("#add").click();
  await page.locator("#protocol").selectOption("rtsp");
  await expect(page.locator("#editor-title")).toHaveText("新建连接");
  await expect(page.locator("#port")).toHaveValue("554");
  await expect(page.locator("#web-address")).not.toBeVisible();
  await expect(page.locator("#transport-note")).toContainText("RTSP over TCP");
  const request=page.waitForRequest(r=>r.method()==="POST"&&r.url().endsWith("/local/connections"));
  await page.locator("#save").click();
  const body=(await request).postDataJSON();
  expect(body.proxy_type).toBe("tcp");expect(body.application_protocol).toBe("rtsp");
  expect(body.local_port).toBe(554);expect(body).not.toHaveProperty("remote_port");expect(body).not.toHaveProperty("subdomain");
});

test("old servers explain the upgrade and retain HTTP creation", async ({page}) => {
  await services(page,undefined);
  await page.locator("#add").click();await page.locator("#protocol").selectOption("tcp");
  await expect(page.locator("#transport-note")).toContainText("升级服务端至 6.1.0");await expect(page.locator("#save")).toBeDisabled();
  await page.locator("#protocol").selectOption("http");await expect(page.locator("#save")).toBeEnabled();await expect(page.locator("#subdomain")).toBeVisible();
});

test("transport deployment and user permission failures are explained separately", async ({page}) => {
  await services(page,{supported:true,tcp:{enabled:true,can_create:false},udp:{enabled:false,can_create:false}});
  await page.locator("#add").click();await page.locator("#protocol").selectOption("ssh");
  await expect(page.locator("#port")).toHaveValue("22");await expect(page.locator("#transport-note")).toContainText("尚未允许普通用户");await expect(page.locator("#save")).toBeDisabled();
  await page.locator("#protocol").selectOption("udp");await expect(page.locator("#transport-note")).toContainText("未开放此传输类型");
});

test("an existing RTSP connection keeps its URI and remains editable after self-service is disabled", async ({page}) => {
  const item={id:"camera",name:"Camera",proxy_type:"tcp",application_protocol:"rtsp",public_endpoint:"camera.example:12000",access_url:"rtsp://camera.example:12000",local_scheme:"http",local_host:"127.0.0.1",local_port:554,enabled:true,version:3,subdomain:"generated-camera"};
  await services(page,{supported:true,tcp:{enabled:true,can_create:false}},[item]);
  await expect(page.locator(".url")).toHaveText("rtsp://camera.example:12000");
  await page.locator('[data-edit="camera"]').click();await expect(page.locator("#protocol")).toHaveValue("rtsp");
  await expect(page.locator("#protocol")).toBeDisabled();await expect(page.locator("#save")).toBeEnabled();await expect(page.locator("#subdomain")).not.toBeVisible();
});

test("desktop login fields have names and theme uses a readable button foreground", async ({
  page,
}) => {
  for (const id of ["server", "username", "password", "new-password", "confirm-password"])
    expect(await page.locator(`#${id}`).evaluate((el) => el.labels.length)).toBe(1);
  await page.locator("#theme-toggle").click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  expect(await page.locator("#login-button").evaluate((el) => getComputedStyle(el).color)).toBe(
    "rgb(15, 23, 42)",
  );
});

test("Enter submits once, shows busy state, and retains input after failure", async ({ page }) => {
  let writes = 0;
  await page.route("**/local/login", async (route) => {
    writes++;
    await new Promise((resolve) => setTimeout(resolve, 350));
    await route.fulfill({ status: 400, json: { message: "登录失败，请重试" } });
  });
  await page.locator("#server").fill("https://console.example.com");
  await page.locator("#username").fill("alice");
  await page.locator("#password").fill("temporary-password");
  await page.locator("#password").press("Enter");
  await expect(page.locator("#login-button")).toBeDisabled();
  await expect(page.locator("#login-error")).toContainText("登录失败");
  await expect(page.locator("#username")).toHaveValue("alice");
  expect(writes).toBe(1);
});

test("required password change is revealed only after the server requests it", async ({ page }) => {
  await expect(page.locator("#password-change")).not.toBeVisible();
  await page.route("**/local/login", (route) =>
    route.fulfill({
      status: 400,
      json: { message: "the account requires a password change; provide --new-password-file" },
    }),
  );
  await page.locator("#server").fill("https://console.example.com");
  await page.locator("#username").fill("alice");
  await page.locator("#password").fill("temporary-password");
  await page.locator("#login-button").click();
  await expect(page.locator("#password-change")).toBeVisible();
  await expect(page.locator("#new-password")).toBeFocused();
});

test("desktop logout failure remains visible and retryable", async ({ page }) => {
  await page.route("**/local/state", (route) =>
    route.fulfill({ json: { enrolled: true, agent_state: "Online", connections: [] } }),
  );
  await page.route("**/local/login", (route) => route.fulfill({ json: { ok: true } }));
  await page.route("**/local/update", (route) => route.fulfill({ json: { newer: false } }));
  await page.locator("#server").fill("https://console.example.com");
  await page.locator("#username").fill("alice");
  await page.locator("#password").fill("temporary-password");
  await page.locator("#login-button").click();
  await expect(page.locator("#home")).toBeVisible();
  await page.route("**/local/logout", (route) =>
    route.fulfill({ status: 500, json: { message: "退出失败，请重试" } }),
  );
  page.on("dialog", (dialog) => dialog.accept());
  await page.locator("#settings-open").click();
  await page.locator("#logout").click();
  await expect(page.locator("#settings-error")).toContainText("退出失败");
  await expect(page.locator("#logout")).toBeEnabled();
});
