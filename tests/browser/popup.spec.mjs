import { readFile } from "node:fs/promises";
import { test, expect } from "@playwright/test";

const root = new URL("../../internal/gui/web/", import.meta.url);
const TOKEN = "popup-session-token";
const inSeconds = (seconds) => new Date(Date.now() + seconds * 1000).toISOString();

// Mocked desktop backend: `state` is served from /local/remote/state and every
// POST is recorded with its auth header.
async function openPopup(page, state, { viewport = { width: 360, height: 224 }, storage = {}, onAction } = {}) {
  await page.setViewportSize(viewport);
  const calls = [];
  for (const [path, type] of [["popup.html", "text/html"], ["popup.js", "text/javascript"], ["popup.css", "text/css"], ["HomeTunnel.svg", "image/svg+xml"]]) {
    await page.route(`**/${path}`, async (route) => route.fulfill({ contentType: type, body: await readFile(new URL(path, root), "utf8") }));
  }
  await page.route("**/local/remote/state", (route) => {
    calls.push({ url: route.request().url(), method: "GET", auth: route.request().headers().authorization });
    return route.fulfill({ json: state });
  });
  for (const path of ["**/local/remote/action", "**/local/remote/popup", "**/local/show"]) {
    await page.route(path, (route) => {
      const request = route.request();
      const call = { url: request.url(), path: new URL(request.url()).pathname, method: request.method(), auth: request.headers().authorization, type: request.headers()["content-type"], body: request.postDataJSON() };
      calls.push(call);
      onAction?.(call, state);
      return route.fulfill({ json: { ok: true } });
    });
  }
  if (Object.keys(storage).length) {
    await page.addInitScript((values) => { for (const [key, value] of Object.entries(values)) localStorage.setItem(key, value); }, storage);
  }
  // A same-URL navigation would only change the fragment; start from a blank page.
  await page.goto("about:blank");
  await page.goto(`/popup.html#session=${TOKEN}`);
  return calls;
}

const posts = (calls, path) => calls.filter((call) => call.method === "POST" && call.path === path);

test("the popup stays empty until the host shows it", async ({ page }) => {
  await openPopup(page, { access_requests: [{ id: "a1", controller_endpoint_id: "ctl-1", expires_at: inSeconds(30) }], pending: [] });
  await expect(page.locator("#request")).toBeHidden();
  await expect(page.locator("#session")).toBeHidden();
});

test("a stranger request shows its details and accepting calls the main window's endpoint", async ({ page }) => {
  const state = { access_requests: [{ id: "req-1", controller_endpoint_id: "7f0c7c6e-controller", expires_at: inSeconds(45) }], pending: [], grants: [] };
  const calls = await openPopup(page, state, { onAction: (call, current) => { if (call.path === "/local/remote/action") current.access_requests = []; } });
  await page.evaluate(() => window.htPopup.show("request"));
  await expect(page.locator("#request")).toBeVisible();
  await expect(page.locator("#request-title")).toHaveText("远程控制请求");
  await expect(page.locator("#request-kind")).toHaveText("有人请求连接这台电脑");
  await expect(page.locator("#request-who")).toHaveText("远程设备");
  await expect(page.locator("#request-device")).toHaveText("7f0c7c6e-controller");
  await expect(page.locator("#request-countdown")).toHaveText(/^(4[0-5]) 秒$/);
  await expect(page.locator("#request-countdown")).toHaveAttribute("role", "timer");
  await expect(page.locator("#request-accept")).toHaveAttribute("aria-label", "接受 远程设备 的远程控制请求");
  await expect(page.locator("#request-reject")).toHaveAttribute("aria-label", "拒绝 远程设备 的远程控制请求");
  await expect(page.locator("#request")).toHaveAttribute("role", "alertdialog");
  // Buttons are inert for a moment so a click meant for something else cannot accept.
  await expect(page.locator("#request-accept")).toBeDisabled();
  await expect(page.locator("#request-accept")).toBeEnabled();
  await page.locator("#request-accept").click();
  await expect.poll(() => posts(calls, "/local/remote/action").map((call) => call.body)).toEqual([{ action: "approve_access_request", id: "req-1" }]);
  await expect(page.locator("#request")).toBeHidden();
  for (const call of calls) {
    expect(call.auth).toBe(`Bearer ${TOKEN}`);
    expect(call.url).not.toContain(TOKEN);
  }
  expect(posts(calls, "/local/remote/action")[0].type).toBe("application/json");
});

test("declining a session request sends the displayed epoch and version", async ({ page }) => {
  const event = { kind: "session", id: "sess-1", controller_endpoint_id: "ctl-9", permissions: ["view", "input.pointer", "input.keyboard"], mode: "one_session", connection_epoch: 4, state_version: 11, expires_at: inSeconds(40) };
  const state = { access_requests: [], pending: [event], grants: [] };
  const calls = await openPopup(page, state, { onAction: (call, current) => { if (call.path === "/local/remote/action") current.pending = []; } });
  await page.evaluate(() => window.htPopup.show("request"));
  await expect(page.locator("#request-kind")).toHaveText("会话请求");
  await expect(page.locator("#request-scopes")).toHaveText("请求权限：屏幕 · 鼠标 · 键盘");
  await page.locator("#request-reject").click();
  await expect.poll(() => posts(calls, "/local/remote/action").map((call) => call.body)).toEqual([{ action: "reject", id: "sess-1", kind: "session", permissions: event.permissions, mode: "one_session", connection_epoch: 4, state_version: 11 }]);
  await expect(page.locator("#request")).toBeHidden();
});

test("accepting a pairing shows the compare code until the user closes it", async ({ page }) => {
  const pairing = { kind: "pairing", id: "pair-1", controller_endpoint_id: "ctl-2", permissions: ["view"], mode: "one_session", expires_at: inSeconds(60) };
  const state = { access_requests: [], pending: [pairing], grants: [] };
  const calls = await openPopup(page, state, {
    onAction: (call, current) => {
      if (call.path === "/local/remote/action") current.pending = [{ ...pairing, kind: "pairing_display", display_code: "482913" }];
      if (call.path === "/local/remote/popup" && call.body.action === "acknowledge") current.pending = [];
    },
  });
  await page.evaluate(() => window.htPopup.show("request"));
  await expect(page.locator("#request-kind")).toHaveText("配对请求 · 仅本次会话");
  await page.locator("#request-accept").click();
  await expect.poll(() => posts(calls, "/local/remote/action")[0]?.body).toEqual({ action: "approve", id: "pair-1", kind: "pairing", permissions: ["view"], mode: "one_session" });
  await expect(page.locator("#request-code-value")).toHaveText("482913");
  await expect(page.locator("#request-kind")).toHaveText("请核对配对码");
  await expect(page.locator("#request-accept")).toBeHidden();
  await expect(page.locator("#request-reject")).toBeHidden();
  await page.locator("#request-ack").click();
  await expect.poll(() => posts(calls, "/local/remote/popup").map((call) => call.body)).toContainEqual({ action: "acknowledge", key: "pairing_display:pair-1" });
  await expect(page.locator("#request")).toBeHidden();
  expect(posts(calls, "/local/remote/action")).toHaveLength(1);
});

test("a long-term pairing can only be declined", async ({ page }) => {
  await openPopup(page, { access_requests: [], pending: [{ kind: "pairing", id: "p9", controller_endpoint_id: "ctl", permissions: ["view"], mode: "persistent", expires_at: inSeconds(60) }] });
  await page.evaluate(() => window.htPopup.show("request"));
  await expect(page.locator("#request-kind")).toHaveText("长期配对请求");
  await expect(page.locator("#request-note")).toHaveText("本机不再提供长期授权，请让对方改用固定密码连接。");
  await expect(page.locator("#request-accept")).toBeHidden();
  await expect(page.locator("#request-reject")).toBeVisible();
});

test("Enter, Escape and scripted clicks never decide a request", async ({ page }) => {
  const calls = await openPopup(page, { access_requests: [{ id: "a1", controller_endpoint_id: "ctl", expires_at: inSeconds(30) }], pending: [] });
  await page.evaluate(() => window.htPopup.show("request"));
  await expect(page.locator("#request-accept")).toBeEnabled();
  await expect(page.locator(":focus")).toHaveCount(0);
  await page.locator("#request-accept").focus();
  await page.keyboard.press("Enter");
  await page.keyboard.press("NumpadEnter");
  await page.locator("#request-reject").focus();
  await page.keyboard.press("Escape");
  await page.evaluate(() => { document.getElementById("request-accept").click(); document.getElementById("request-accept").dispatchEvent(new MouseEvent("click", { bubbles: true })); });
  await page.waitForTimeout(400);
  expect(posts(calls, "/local/remote/action")).toHaveLength(0);
  await expect(page.locator("#request")).toBeVisible();
});

test("queued requests show the newest with a count and expired ones close", async ({ page }) => {
  const state = { access_requests: [{ id: "first", controller_endpoint_id: "ctl-first", expires_at: inSeconds(6) }], pending: [] };
  const calls = await openPopup(page, state);
  await page.evaluate(() => window.htPopup.show("request"));
  await expect(page.locator("#request-device")).toHaveText("ctl-first");
  await expect(page.locator("#request-queue")).toBeHidden();
  // Record the accept button's state the moment the new request replaces the old one.
  await page.evaluate(() => {
    const device = document.getElementById("request-device");
    new MutationObserver(() => { if (device.textContent === "ctl-second" && window.acceptWhenSwapped === undefined) window.acceptWhenSwapped = document.getElementById("request-accept").disabled; })
      .observe(device, { childList: true, characterData: true, subtree: true });
  });
  state.access_requests = [...state.access_requests, { id: "second", controller_endpoint_id: "ctl-second", expires_at: inSeconds(30) }];
  await expect(page.locator("#request-device")).toHaveText("ctl-second");
  await expect(page.locator("#request-queue")).toHaveText("还有 1 个请求等待处理");
  // Accepting the new request must not be possible the instant it replaces the old one.
  expect(await page.evaluate(() => window.acceptWhenSwapped)).toBe(true);
  // Once the first request expires only the second one remains.
  await expect(page.locator("#request-queue")).toBeHidden({ timeout: 9000 });
  await expect(page.locator("#request-device")).toHaveText("ctl-second");
  state.access_requests = state.access_requests.filter((item) => item.id !== "second");
  await expect(page.locator("#request")).toBeHidden({ timeout: 5000 });
  expect(posts(calls, "/local/remote/popup").some((call) => call.body.action === "refresh")).toBe(true);
});

test("the countdown turns urgent near expiry and the popup closes at zero", async ({ page }) => {
  const calls = await openPopup(page, { access_requests: [{ id: "a1", controller_endpoint_id: "ctl", expires_at: inSeconds(3) }], pending: [] });
  await page.evaluate(() => window.htPopup.show("request"));
  await expect(page.locator("#request-countdown")).toHaveAttribute("data-urgent", "true");
  await expect(page.locator("#request")).toBeHidden({ timeout: 6000 });
  await expect.poll(() => posts(calls, "/local/remote/popup").map((call) => call.body.action)).toContain("refresh");
  expect(posts(calls, "/local/remote/action")).toHaveLength(0);
});

test("the session indicator disconnects through the existing stop action", async ({ page }) => {
  const state = { active_session_id: "live-1", access_requests: [], pending: [], grants: [{ id: "g1", session_id: "live-1", controller_endpoint_id: "ctl-live" }] };
  const calls = await openPopup(page, state, { viewport: { width: 320, height: 60 } });
  await page.evaluate(() => window.htPopup.show("session"));
  await expect(page.locator("#session")).toBeVisible();
  await expect(page.locator("#session-title")).toHaveText("正在被远程控制");
  await expect(page.locator("#session-who")).toHaveText("ctl-live");
  await expect(page.locator("#session-stop")).toHaveAttribute("aria-label", "断开远程控制");
  await page.locator("#session-open").click();
  await page.locator("#session-stop").click();
  await expect.poll(() => posts(calls, "/local/remote/action").map((call) => call.body)).toEqual([{ action: "stop" }]);
  expect(posts(calls, "/local/show")).toHaveLength(1);
  await page.evaluate(() => window.htPopup.hide());
  await expect(page.locator("#session")).toBeHidden();
});

test("popup content fits its window without scrolling in both languages and themes", async ({ page }) => {
  const request = { access_requests: [], pending: [{ kind: "session", id: "s1", controller_endpoint_id: "a-very-long-controller-endpoint-identifier-0123456789", permissions: ["view", "input.keyboard", "input.pointer", "input.text", "audio.system", "clipboard.read", "clipboard.write", "files.send", "files.receive"], expires_at: inSeconds(60) }, { kind: "pairing", id: "p1", controller_endpoint_id: "ctl", permissions: ["view"], expires_at: inSeconds(60) }] };
  for (const storage of [{}, { ht_locale: "en", ht_theme: "dark" }]) {
    await page.unrouteAll({ behavior: "ignoreErrors" });
    await openPopup(page, request, { storage });
    await page.evaluate(() => window.htPopup.show("request"));
    await expect(page.locator("#request-queue")).toBeVisible();
    const layout = await page.evaluate(() => {
      const box = (id) => document.getElementById(id).getBoundingClientRect().toJSON();
      const doc = document.scrollingElement;
      return { width: innerWidth, height: innerHeight, scroll: [doc.scrollWidth, doc.scrollHeight], card: box("request"), accept: box("request-accept"), reject: box("request-reject"), countdown: box("request-countdown"), queue: box("request-queue"), scopes: box("request-scopes"), who: box("request-who"), footer: document.querySelector(".popup-actions").getBoundingClientRect().toJSON() };
    });
    expect(layout.scroll[0]).toBeLessThanOrEqual(layout.width);
    expect(layout.scroll[1]).toBeLessThanOrEqual(layout.height);
    for (const name of ["accept", "reject", "countdown", "queue", "scopes", "who", "footer"]) {
      const rect = layout[name];
      expect(rect.left, name).toBeGreaterThanOrEqual(0);
      expect(rect.right, name).toBeLessThanOrEqual(layout.width);
      expect(rect.bottom, name).toBeLessThanOrEqual(layout.height);
      expect(rect.width, name).toBeGreaterThan(0);
    }
    expect(layout.accept.height).toBeGreaterThanOrEqual(32);
    expect(layout.accept.left).toBeGreaterThan(layout.reject.right);
    expect(layout.scopes.bottom).toBeLessThanOrEqual(layout.footer.top);
    if (storage.ht_locale === "en") {
      await expect(page.locator("#request-accept")).toHaveText("Accept");
      await expect(page.locator("#request-reject")).toHaveText("Decline");
      await expect(page.locator("#request-title")).toHaveText("Remote control request");
      await expect(page.locator("#request-queue")).toHaveText("1 more waiting");
      await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
      expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgb(34, 38, 60)");
      const han = await page.evaluate(() => [...document.querySelectorAll("#request *")].filter((node) => node.children.length === 0 && node.getClientRects().length && !node.closest("[data-no-translate]") && /\p{Script=Han}/u.test(node.textContent)).map((node) => node.textContent));
      expect(han).toEqual([]);
    } else {
      expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgb(255, 255, 255)");
    }
  }
  await page.unrouteAll({ behavior: "ignoreErrors" });
  await openPopup(page, { active_session_id: "live", access_requests: [], pending: [], grants: [] }, { viewport: { width: 320, height: 60 } });
  await page.evaluate(() => window.htPopup.show("session"));
  const bar = await page.evaluate(() => ({ stop: document.getElementById("session-stop").getBoundingClientRect().toJSON(), scroll: [document.scrollingElement.scrollWidth, document.scrollingElement.scrollHeight] }));
  expect(bar.scroll).toEqual([320, 60]);
  expect(bar.stop.right).toBeLessThanOrEqual(320);
  expect(bar.stop.bottom).toBeLessThanOrEqual(60);
  const scrollbars = await page.evaluate(() => getComputedStyle(document.documentElement).scrollbarWidth);
  expect(scrollbars).toBe("none");
});

test("popup palette matches the main window", async ({ page }) => {
  const popupCss = await readFile(new URL("popup.css", root), "utf8");
  const desktopCss = await readFile(new URL("desktop.css", root), "utf8");
  const variables = (css, selector) => {
    const block = css.slice(css.indexOf(selector)); const body = block.slice(block.indexOf("{") + 1, block.indexOf("}"));
    return Object.fromEntries([...body.matchAll(/--([\w-]+):\s*([^;]+);/g)].map((match) => [match[1], match[2].trim()]));
  };
  for (const selector of [":root", "html[data-theme=dark]"]) {
    const popup = variables(popupCss, selector), desktop = variables(desktopCss, selector);
    for (const name of ["bg", "fg", "muted", "card", "line", "accent", "accent-fg", "secondary", "secondary-fg"]) expect(popup[name], `${selector} --${name}`).toBe(desktop[name]);
  }
  expect(page).toBeTruthy();
});

test("the popup never sits on screen as an empty card", async ({ page }) => {
  // The host sizes the window before the page has state; the session bar shows straight away.
  const state = { active_session_id: "live-2", access_requests: [], pending: [], grants: [] };
  const calls = await openPopup(page, state, { viewport: { width: 320, height: 60 } });
  await page.route("**/local/remote/state", () => {});
  await page.evaluate(() => window.htPopup.show("session"));
  await expect(page.locator("#session")).toBeVisible();
  await page.unroute("**/local/remote/state");
  // A request answered elsewhere leaves nothing to show: the host is asked to re-check at once.
  await page.route("**/local/remote/state", (route) => route.fulfill({ json: { access_requests: [], pending: [], grants: [] } }));
  await page.evaluate(() => window.htPopup.show("request"));
  await expect.poll(() => posts(calls, "/local/remote/popup").some((call) => call.body.action === "refresh")).toBe(true);
});

test("native reveal waits for ready and populated request content", async ({page}) => {
  await page.addInitScript(()=>{window.nativeMessages=[];window.chrome??={};window.chrome.webview={postMessage:message=>window.nativeMessages.push(message)};});
  await openPopup(page,{access_requests:[{id:"r-ready",controller_endpoint_id:"peer",expires_at:inSeconds(40)}],pending:[]});
  await expect.poll(()=>page.evaluate(()=>window.nativeMessages)).toEqual(["ht-popup:ready"]);
  let release;
  await page.route("**/local/remote/state",async route=>{
    await new Promise(resolve=>{release=resolve;});
    await route.fulfill({json:{access_requests:[{id:"r-ready",controller_endpoint_id:"peer",expires_at:inSeconds(40)}],pending:[]}});
  });
  await page.evaluate(()=>window.htPopup.show("request"));
  await expect.poll(()=>!!release).toBe(true);
  expect(await page.evaluate(()=>window.nativeMessages)).toEqual(["ht-popup:ready"]);
  release();
  await expect.poll(()=>page.evaluate(()=>window.nativeMessages)).toContain("ht-popup:rendered:request");
  await expect(page.locator("#request")).toBeVisible();
  await page.unroute("**/local/remote/state");
  await page.route("**/local/remote/state",route=>route.fulfill({json:{access_requests:[],pending:[]}}));
  await expect.poll(()=>page.evaluate(()=>window.nativeMessages)).toContain("ht-popup:empty:request");
});

test("reopening a session after an empty request discards stale state and stays opaque", async ({page}) => {
  await page.addInitScript(()=>{window.nativeMessages=[];window.chrome??={};window.chrome.webview={postMessage:message=>window.nativeMessages.push(message)};});
  await openPopup(page,{access_requests:[],pending:[]},{viewport:{width:320,height:60}});
  await page.evaluate(()=>window.htPopup.show("request"));
  await page.route("**/local/remote/state",()=>{});
  await page.evaluate(()=>{window.htPopup.hide();window.htPopup.show("session");});
  await expect(page.locator("#session")).toBeVisible();
  await expect.poll(()=>page.evaluate(()=>window.nativeMessages)).toContain("ht-popup:rendered:session");
  for(const selector of ["html","body","#session"]){
    const style=await page.locator(selector).evaluate(el=>({background:getComputedStyle(el).backgroundColor,opacity:getComputedStyle(el).opacity}));
    expect(style.background).toBe("rgb(255, 255, 255)");
    expect(style.opacity).toBe("1");
  }
  await page.evaluate(()=>window.htPopup.hide());
  await expect(page.locator("#session")).toBeHidden();
  await page.evaluate(()=>window.htPopup.show("session"));
  await expect(page.locator("#session")).toBeVisible();
});
