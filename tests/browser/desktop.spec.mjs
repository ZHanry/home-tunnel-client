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
  await page.route("**/desktop.css", async (route) =>
    route.fulfill({
      contentType: "text/css",
      body: await readFile(new URL("desktop.css", root), "utf8"),
    }),
  );
  await page.route("**/local/state", (route) => route.fulfill({ json: { enrolled: false } }));
  await page.route("**/local/remote/state", route => route.fulfill({json:{enrolled:false,enabled:false,capabilities:{available:false},pending:[],grants:[]}}));
  await page.goto("/desktop-preview");
});

test("an unenrolled host with null lists offers enrollment instead of a status error", async ({page}) => {
  // Shape returned by a real 10.0.0 worker before the host has ever enrolled.
  await page.route("**/local/remote/state",route=>route.fulfill({json:{enrolled:false,enabled:false,running:false,endpoint_id:"",capabilities:{available:true,status:"ready",permissions:["view"]},pending:[],grants:[],invites:null,access_profile:{device_id:"",fixed_password_enabled:false,revision:0},access_requests:null,files:null,emergency_key:"X",service:{installed:false,running:false}}}));
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-host-status")).toHaveText("远程连接已关闭");
  await expect(page.locator("#rd-host-enroll")).toBeVisible();
  await expect(page.locator("#rd-host-enable")).toBeHidden();
  await expect(page.locator(".remote-security-card")).toBeHidden();
  await expect(page.getByText("授权与会话")).toHaveCount(0);
});

test("the host card shows a grouped 9-digit device ID and controllers accept spaced input", async ({page}) => {
  const state={enrolled:true,enabled:true,running:true,setup:"pending",capabilities:{available:true,status:"ready"},pending:[],grants:[],access_profile:{device_id:"",fixed_password_enabled:false,revision:0}};
  await page.route("**/local/remote/state",route=>route.fulfill({json:state}));
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-host-status")).toHaveText("正在开启远程协助…");
  await expect(page.locator("#rd-host-enroll")).toBeHidden();
  state.setup=""; state.access_profile.device_id="482913570";
  await page.evaluate(()=>refreshRemoteHost());
  await expect(page.locator("#rd-host-code")).toHaveText("482 913 570");
  await expect(page.locator("#rd-host-status")).toHaveText("已允许连接");
  await expect(page.locator("#rd-host-copy")).toBeEnabled();
  await page.evaluate(()=>{ navigator.clipboard.writeText=async text=>{ window.copied=text; }; });
  await page.locator("#rd-host-copy").click();
  await expect.poll(()=>page.evaluate(()=>window.copied)).toBe("482913570");
  const opened=[];
  await page.route("**/local/remote/window",route=>{ opened.push(route.request().postDataJSON()); return route.fulfill({json:{ok:true}}); });
  await page.locator("#remote-device-id").fill(" 123 456-789 ");
  await page.locator("#remote-connect-form button").click();
  await expect.poll(()=>opened[0]).toEqual({assist:true,access_id:"123456789"});
});

test("remote backend stays unavailable and the upgrade path needs only the account password", async ({page}) => {
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.evaluate(()=>localStorage.setItem("ht_username","alice"));
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-host-status")).toContainText("没有可用的远控后端");
  await expect(page.locator("#rd-host-enable")).toBeDisabled();
  await expect(page.locator("#rd-host-enroll")).toBeHidden();
  await page.route("**/local/remote/state",route=>route.fulfill({json:{enrolled:false,enabled:false,capabilities:{available:true,permissions:["view"]},pending:[],grants:[]}}));
  await page.evaluate(()=>refreshRemoteHost());
  await expect(page.locator("#rd-host-enroll")).toBeVisible();
  await expect(page.locator("#remote-host-card #rd-host-enroll")).toBeVisible();
  await expect(page.locator("#rd-host-user")).toHaveValue("alice");
  await page.locator("#rd-host-password").fill("temporary-password");
  await expect(page.locator("#rd-host-enroll-submit")).toBeEnabled();
  await expect(page.locator("#rd-host-mfa")).toBeHidden();
  const attempts=[];
  await page.route("**/local/remote/action",route=>{
    attempts.push(route.request().postDataJSON());
    return attempts.length===1
      ? route.fulfill({status:401,json:{error_code:"RD_MFA_REQUIRED",message:"Dynamic code required"}})
      : attempts.length===2 ? route.fulfill({status:401,json:{error_code:"RD_MFA_INVALID",message:"Invalid code"}})
      : route.fulfill({json:{ok:true}});
  });
  await page.locator("#rd-host-enroll-submit").click();
  await expect(page.locator("#rd-host-mfa")).toBeVisible();
  await expect(page.locator("#rd-host-mfa-feedback")).toHaveText("请输入动态码或恢复码。");
  await expect(page.locator("#rd-host-error")).toBeEmpty();
  await expect(page.locator("#rd-host-mfa")).toHaveAttribute("aria-invalid", "false");
  const mfaBox = await page.locator("#rd-host-mfa").boundingBox();
  const hintBox = await page.locator("#rd-host-mfa-feedback").boundingBox();
  const submitBox = await page.locator("#rd-host-enroll-submit").boundingBox();
  expect(hintBox.y).toBeGreaterThan(mfaBox.y + mfaBox.height);
  expect(submitBox.y).toBeGreaterThan(hintBox.y + hintBox.height);
  expect(attempts[0].mfa_code).toBe("");
  expect(attempts[0].trust_pin).toBe("");
  await page.locator("#rd-host-password").fill("temporary-password");
  await page.locator("#rd-host-mfa").fill("123456");
  await page.locator("#rd-host-enroll-submit").click();
  await expect.poll(()=>attempts.length).toBe(2);
  await expect(page.locator("#rd-host-mfa-feedback")).toHaveText("动态码或恢复码无效，请重试。");
  await expect(page.locator("#rd-host-mfa")).toHaveAttribute("aria-invalid", "true");
  await page.locator("#rd-host-password").fill("temporary-password");
  await page.locator("#rd-host-mfa").fill("234567");
  await expect(page.locator("#rd-host-mfa")).toHaveAttribute("aria-invalid", "false");
  await page.locator("#rd-host-enroll-submit").click();
  await expect.poll(()=>attempts.length).toBe(3);
  expect(attempts[1].action).toBe("enroll");
  expect(attempts[1].mfa_code).toBe("123456");
  await expect(page.locator("#rd-host-password")).toHaveValue("");
  await expect(page.locator("#rd-host-mfa")).toHaveValue("");
});

test("local approval lists every requested permission and pairing code cannot grant twice", async ({page}) => {
  const event={kind:"pairing",id:"pair-one",controller_endpoint_id:"controller-a",controller_thumbprint:"public-fingerprint",permissions:["view","audio.microphone","files.send"],mode:"one_session"};
  await page.route("**/local/remote/state",route=>route.fulfill({json:{enrolled:true,enabled:true,running:true,capabilities:{available:true},pending:[event],grants:[]}}));
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-host-pending")).toContainText("麦克风回传");
  await expect(page.locator("#rd-host-pending")).toContainText("发送文件到本机");
  let action;
  await page.route("**/local/remote/action",route=>{action=route.request().postDataJSON();event.kind="pairing_display";event.display_code="123456";return route.fulfill({json:{ok:true}});});
  await page.locator("#rd-host-pending").getByRole("button",{name:"允许以上权限"}).click();
  await expect.poll(()=>action?.action).toBe("approve");
  expect(action.permissions).toEqual(event.permissions);
  await expect(page.locator("#rd-host-pending")).toContainText("123456");
  await expect(page.locator("#rd-host-pending button")).toHaveCount(0);
});

test("unattended access is the fixed password and no separate unattended mode remains", async ({page}) => {
  const state = {enrolled:true,enabled:true,running:true,unattended_enabled:false,capabilities:{available:true,unattended_enabled:false},service:{installed:true,running:true},pending:[{kind:"pairing",id:"pair-long",controller_endpoint_id:"controller-a",permissions:["view"],mode:"persistent"}],grants:[],access_profile:{device_id:"123456789",fixed_password_enabled:false,revision:1}};
  const actions = [];
  await page.route("**/local/remote/state",route=>route.fulfill({json:state}));
  await page.route("**/local/remote/action",route=>{
    const action=route.request().postDataJSON();actions.push(action);
    if (action.action==="disable_unattended") state.unattended_enabled=false;
    if (action.action==="reject") state.pending=[];
    return route.fulfill({json:{ok:true}});
  });
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-host-code")).toHaveText("123 456 789");
  await expect(page.locator(".remote-tabs, [data-remote-tab]")).toHaveCount(0);
  await expect(page.locator('[id^="rd-unattended"], .remote-unattended, .remote-unattended-binding')).toHaveCount(0);
  await expect(page.locator("#remote-page").getByText("可信设备")).toHaveCount(0);
  await expect(page.locator(".remote-access-card h3").first()).toHaveText("固定密码（无人值守）");
  await expect(page.locator(".remote-access-card")).toContainText("无需你在本机同意");
  await expect(page.locator("#rd-fixed-password")).toBeVisible();
  // The only 无人值守 copy left describes the fixed password; no other control offers it.
  const unattendedText = await page.locator("#remote-page").evaluate(root => {
    const found = [], walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) if (node.nodeValue.includes("无人值守") && node.parentElement.getClientRects().length) found.push(node.parentElement.closest("#remote-host-card, .remote-access-card")?.className || node.parentElement.tagName);
    return found;
  });
  expect(unattendedText.length).toBeGreaterThan(0);
  expect(unattendedText.every(owner => /remote-local-card|remote-access-card/.test(owner))).toBe(true);
  await expect(page.locator("#remote-page button, #remote-page option, #remote-page label").filter({hasText:"无人值守"})).toHaveCount(0);
  await expect(page.locator("#rd-fixed-scope")).toBeVisible();
  // A controller still asking for long-term trust can only be rejected.
  await expect(page.locator("#rd-host-pending")).toContainText("改用固定密码");
  await expect(page.locator("#rd-host-pending button")).toHaveCount(1);
  await page.locator("#rd-host-pending").getByRole("button",{name:"拒绝"}).click();
  await expect.poll(()=>actions.at(-1)?.action).toBe("reject");
  // Installs that enabled the retired mode can still turn it off.
  await expect(page.locator("#rd-legacy-trust")).toBeHidden();
  state.unattended_enabled=true;
  await page.evaluate(()=>refreshRemoteHost());
  await expect(page.locator("#rd-legacy-trust")).toBeVisible();
  await page.locator("#rd-legacy-disable").click();
  await expect(page.locator("#rd-legacy-trust")).toBeHidden();
  expect(actions.map(action=>action.action)).toEqual(["reject","disable_unattended"]);
  expect(actions.some(action=>action.action==="enable_unattended")).toBe(false);
});

test("fixed password and access requests use the host settings without retaining secrets", async ({ page }) => {
  const state = {
    enrolled: true, enabled: true, running: true, fixed_revision: 1, emergency_key: "X",
    capabilities: { available: true, unattended_enabled: false }, pending: [], grants: [],
    access_profile: { device_id: "123456789", fixed_password_enabled: false, revision: 1 },
    access_requests: [{ id: "request-one", controller_endpoint_id: "visitor-device", expires_at: new Date(Date.now() + 120000).toISOString() }],
  };
  const actions = [];
  await page.route("**/local/remote/state", route => route.fulfill({ json: state }));
  await page.route("**/local/remote/action", route => {
    const action = route.request().postDataJSON(); actions.push(action);
    if (action.action === "set_fixed_password") {
      state.fixed_revision = 2;
      state.access_profile = { ...state.access_profile, fixed_password_enabled: true, revision: 2 };
    }
    if (action.action === "approve_access_request") state.access_requests = [];
    if (action.action === "set_emergency_hotkey") state.emergency_key = action.emergency_key;
    return route.fulfill({ json: { ok: true } });
  });
  await services(page, undefined);
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-host-code")).toHaveText("123 456 789");
  await expect(page.locator("#rd-fixed-status")).toContainText("未设置固定密码");
  await page.locator("#rd-fixed-password").fill("strong-fixed-password");
  await page.locator("#rd-fixed-save").click();
  await expect(page.locator("#rd-fixed-password")).toHaveValue("");
  await expect(page.locator("#rd-fixed-status")).toContainText("固定密码已启用");
  await expect(page.locator("#rd-access-requests")).toContainText("visitor-device");
  await page.locator("#rd-access-requests button").first().click();
  await expect(page.locator("#rd-access-requests")).toContainText("暂无请求");
  await page.locator("#rd-emergency-key").selectOption("F12");
  await expect.poll(() => actions.at(-1)?.emergency_key).toBe("F12");
  expect(actions.map(action => action.action)).toEqual(["set_fixed_password", "approve_access_request", "set_emergency_hotkey"]);
  await page.reload();
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-fixed-password")).toHaveValue("");
});

test("temporary assistance shows its password once and retains revocation after reload", async ({ page }) => {
  const invite = { id: "invite-one", device_id: "123456789", temporary_password: ["ABcd", "2345", "EFgh"].join(""), expires_at: new Date(Date.now() + 300000).toISOString() };
  let invites = [];
  let enabled = true;
  const actions = [];
  await page.route("**/local/remote/state", route => route.fulfill({ json: { enrolled: true, enabled, running: enabled, capabilities: { available: true }, pending: [], grants: [], invites } }));
  await page.route("**/local/remote/action", route => {
    const action = route.request().postDataJSON(); actions.push(action);
    if (action.action === "create_invite") {
      invites = [{ id: invite.id, device_id: invite.device_id, state: "active", expires_at: invite.expires_at }];
      return route.fulfill({ json: invite });
    }
    invites = [];
    if (action.action === "disable") enabled = false;
    return route.fulfill({ json: { ok: true } });
  });
  await services(page, undefined);
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-assist-create")).toBeEnabled();
  await expect(page.locator("#rd-assist-secret")).toBeHidden();
  await page.locator("#rd-assist-create").click();
  await expect(page.locator("#rd-assist-secret")).toContainText(invite.temporary_password);
  expect(actions[0].action).toBe("create_invite");
  await page.reload();
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-assist-secret")).toBeHidden();
  await expect(page.locator("#rd-assist-list")).toContainText(invite.device_id);
  await page.locator("#rd-assist-list button").click();
  await expect.poll(() => actions.at(-1)?.action).toBe("revoke_invite");
  await expect(page.locator("#rd-assist-list")).toBeEmpty();
  await page.locator("#rd-assist-create").click();
  await expect(page.locator("#rd-assist-secret")).toContainText(invite.temporary_password);
  await page.locator("#rd-host-disable").click();
  await expect(page.locator("#rd-assist-secret")).toBeHidden();
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

test("device navigation shows account devices without interpreting names as HTML", async ({ page }) => {
  await page.route("**/local/state", route => route.fulfill({json:{enrolled:true,agent_state:"Online",console_url:"https://server.example",connections:[]}}));
  await page.route("**/local/devices", route => route.fulfill({json:{local_device_id:"local",items:[
    {id:"local",name:"这台电脑",status:"active",online:true},
    {id:"remote",name:"<img src=x onerror=alert(1)>",status:"active",online:true},
  ]}}));
  await page.reload();
  await page.locator("#nav-devices").click();
  await expect(page.locator("#devices-page")).toBeVisible();
  await expect(page.locator("#devices-list")).toContainText("<img src=x onerror=alert(1)>");
  await expect(page.locator("#devices-list img")).toHaveCount(0);
  await page.locator("#devices-search").fill("remote");
  await expect(page.locator(".account-device-card")).toHaveCount(1);
  await page.locator("#nav-remote").click();
  await expect(page.locator("#recent-devices-list")).toContainText("<img src=x onerror=alert(1)>");
});

test("a device opens its own native remote viewer instead of a browser tab", async ({ page }) => {
  await page.route("**/local/state", route => route.fulfill({json:{enrolled:true,agent_state:"Online",console_url:"https://server.example",connections:[]}}));
  const deviceId = "12345678-1234-1234-1234-123456789abc";
  await page.route("**/local/devices", route => route.fulfill({json:{local_device_id:"local",items:[{id:deviceId,name:"Living room",status:"active",online:true}]}}));
  await page.reload();
  await expect(page.locator("#remote-connect-list .remote-connect-device")).toHaveCount(1);
  const opened = [];
  await page.route("**/local/remote/window", route => { opened.push(route.request().postDataJSON()); return route.fulfill({json:{ok:true}}); });
  await page.evaluate(() => { window.open = (...args) => { window.remoteOpen = args; }; });
  await page.locator("#remote-connect-list .remote-connect-device").click();
  await expect.poll(() => opened[0]?.device_id).toBe(deviceId);
  await page.locator("#remote-device-id").fill(deviceId);
  await page.locator("#remote-connect-form button").click();
  await expect.poll(() => opened[1]?.device_id).toBe(deviceId);
  await page.locator("#remote-device-id").fill("another-device");
  await page.locator("#remote-connect-form button").click();
  await expect(page.locator("#remote-open-error")).toContainText("未找到或当前离线");
  await page.locator("#remote-open-assist").click();
  await expect.poll(() => opened[2]?.assist).toBe(true);
  expect(opened[2].device_id).toBeUndefined();
  expect(opened).toHaveLength(3);
  expect(await page.evaluate(() => window.remoteOpen)).toBeUndefined();
});

test("session files request local selection with the displayed epoch and render names as text", async ({page}) => {
  const files = {session_id:"session-file",connection_epoch:3,can_send:true,can_receive:true,items:[{event:"offer",id:"file-one",name:"<img src=x onerror=alert(1)>.txt",size:24,outgoing:false}]};
  await page.route("**/local/remote/state",route=>route.fulfill({json:{enrolled:true,enabled:true,running:true,capabilities:{available:true},pending:[],grants:[],files}}));
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-host-files")).toContainText(files.items[0].name);
  await expect(page.locator("#rd-host-files img")).toHaveCount(0);
  const actions=[];
  await page.route("**/local/remote/files",route=>{actions.push(route.request().postDataJSON());return route.fulfill({json:{ok:true,cancelled:true}});});
  await page.getByRole("button",{name:"选择保存位置"}).click();
  await expect.poll(()=>actions.length).toBe(1);
  expect(actions[0]).toEqual({action:"receive",id:"file-one",session_id:"session-file",connection_epoch:3});
  await page.getByRole("button",{name:"选择多个文件发送"}).click();
  await expect.poll(()=>actions.length).toBe(2);
  expect(actions[1]).toEqual({action:"send",session_id:"session-file",connection_epoch:3});
  files.items[0]={...files.items[0],event:"error",may_be_saved:true,error_code:"RD_FILE_CANCELLED"};
  await page.evaluate(()=>refreshRemoteHost());
  await expect(page.locator("#rd-host-files")).toContainText("文件可能已保存");
  await expect(page.getByRole("button",{name:"选择保存位置"})).toHaveCount(0);
  files.session_id="";
  await page.evaluate(()=>refreshRemoteHost());
  await expect(page.locator("#rd-host-files")).toBeEmpty();
});

async function services(page, capabilities, connections = []) {
  await page.route("**/local/state", route => route.fulfill({json:{enrolled:true,agent_state:"Online",capabilities,connections}}));
  await page.route("**/local/update", route => route.fulfill({json:{newer:false}}));
  await page.reload();
  await page.locator("#nav-tunnels").click();
  await expect(page.locator("#home")).toBeVisible();
}

test("English navigation and live locale changes preserve user names and drafts", async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem("ht_locale", "en"));
  await page.route("**/local/devices", route => route.fulfill({ json: { local_device_id: "local", items: [
    { id: "peer", name: "设置", status: "active", online: true },
  ] } }));
  await page.route("**/local/device/metadata", route => route.fulfill({ json: { tags: ["home"], metadata_version: 1 } }));
  const connection = { id: "service", name: "在线", enabled: true, proxy_type: "http", local_host: "127.0.0.1", local_port: 8080, state: "Online" };
  await services(page, undefined, [connection]);
  const untranslated = () => page.evaluate(() => {
    const found = [], walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      const parent = node.parentElement;
      if (!parent.closest("script,style,[data-no-translate],.service-identity strong,#locale-toggle,#sidebar-locale")
          && parent.getClientRects().length && /\p{Script=Han}/u.test(node.nodeValue)) found.push(node.nodeValue.trim());
    }
    return found;
  });
  for (const tab of ["remote", "devices", "tunnels", "settings"]) {
    await page.locator("#nav-" + tab).click();
    await expect.poll(untranslated).toEqual([]);
  }
  await page.locator("#nav-devices").click();
  await expect(page.locator("#devices-list [data-no-translate]")).toHaveText("设置");
  await page.locator("#sidebar-locale").click();
  await expect(page.locator("#nav-devices")).toContainText("我的设备");
  await expect(page.locator("#devices-list [data-no-translate]")).toHaveText("设置");
  await page.locator("#sidebar-locale").click();
  await expect(page.locator("#nav-devices")).toContainText("My devices");
  await page.locator("#nav-tunnels").click();
  await expect(page.locator(".service-identity strong")).toHaveText("在线");
  await page.locator("#nav-settings").click();
  await expect(page.locator("#device-tags, #theme-preference, #settings-back, #nav-updates")).toHaveCount(0);
  await page.locator("#sidebar-locale").click();
  await expect(page.locator("#settings-update h2")).toHaveText("软件更新");
});

test("system theme follows the OS and persists while explicit light mode stays fixed", async ({ page }) => {
  await page.addInitScript(() => { if (!localStorage.getItem("ht_theme")) localStorage.setItem("ht_theme", "system"); });
  await page.emulateMedia({ colorScheme: "dark" });
  await page.route("**/local/device/metadata", route => route.fulfill({ json: { tags: [], metadata_version: 1 } }));
  await services(page, undefined);
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await expect(page.locator("html")).toHaveAttribute("data-theme-preference", "system");
  await page.emulateMedia({ colorScheme: "light" });
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  await page.reload();
  expect(await page.evaluate(() => localStorage.getItem("ht_theme"))).toBe("system");
  await page.locator("#nav-settings").click();
  await page.locator("#sidebar-theme").click();
  await page.locator("#sidebar-theme").click();
  await page.emulateMedia({ colorScheme: "dark" });
  await expect.poll(() => page.evaluate(() => matchMedia("(prefers-color-scheme: dark)").matches)).toBe(true);
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
  expect(await page.evaluate(() => localStorage.getItem("ht_theme"))).toBe("light");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
});

test("batch selection confirms the affected names and preserves each result", async ({page}) => {
  const connections = ["one", "two"].map((id,index)=>({id,device_id:"local",name:`Service ${index+1}`,proxy_type:"http",enabled:true,version:index+3,local_host:"127.0.0.1",local_port:8080}));
  await services(page,undefined,connections);
  let body;
  await page.route("**/local/batch",route=>{body=route.request().postDataJSON();return route.fulfill({json:{results:[{id:"one",status:200},{id:"two",status:409,error_code:"VERSION_CONFLICT"}]}});});
  await page.locator('[data-select="one"]').check();
  await page.locator('[data-select="two"]').check();
  page.once("dialog",async dialog=>{expect(dialog.message()).toContain("Service 1");expect(dialog.message()).toContain("Service 2");await dialog.accept();});
  await page.locator("#batch-pause").click();
  await expect(page.locator("#batch-results")).toContainText("Service 1: 已保存");
  await expect(page.locator("#batch-results")).toContainText("Service 2: VERSION_CONFLICT");
  expect(body).toEqual({enabled:false,items:[{id:"one",expected_version:3},{id:"two",expected_version:4}]});
});

test("settings include updates and the server on first navigation without metadata", async ({page}) => {
  await page.route("**/local/state", route => route.fulfill({json:{enrolled:true,console_url:"https://console.example.test",device_name:"My PC",version:"10.1.0",connections:[]}}));
  await page.route("**/local/devices", route => route.fulfill({json:{local_device_id:"local",items:[]}}));
  await page.route("**/local/update", route => route.fulfill({json:{current:"10.1.0",newer:false}}));
  let metadataCalls = 0;
  await page.route("**/local/device/metadata", route => { ++metadataCalls; return route.fulfill({json:{}}); });
  await page.reload();
  await expect(page.locator("#remote-page")).toBeVisible();
  await page.locator("#nav-settings").click();
  await expect(page.locator("#settings-server")).toHaveText("https://console.example.test");
  await expect(page.locator("#settings-update")).toBeVisible();
  await expect(page.locator("#update-current-version")).toHaveText("10.1.0");
  await expect(page.locator("#device-tags, #device-favorite, #metadata-save, #theme-preference, #settings-back, #nav-updates")).toHaveCount(0);
  expect(metadataCalls).toBe(0);
});

test("RTSP preset creates TCP with an automatic port and no required web subdomain", async ({page}) => {
  await services(page,{supported:true,tcp:{enabled:true,can_create:true},udp:{enabled:true,can_create:true}});
  await page.route("**/local/connection-check", route => route.fulfill({json:{status:"pass",code:"TARGET_TCP_READY"}}));
  await page.route("**/local/connections", route => route.fulfill({json:{id:"camera"}}));
  await page.locator("#add").click();
  await page.locator("#protocol").selectOption("rtsp");
  await expect(page.locator("#editor-title")).toHaveText("新建连接");
  await expect(page.locator("#port")).toHaveValue("554");
  await expect(page.locator("#web-address")).not.toBeVisible();
  await expect(page.locator("#transport-note")).toContainText("RTSP over TCP");
  await page.locator("#wizard-next").click();
  await expect(page.locator("#wizard-next")).toBeDisabled();
  await page.locator("#target-check").click();
  await expect(page.locator("#target-result")).toContainText("本地 TCP 端口可连接");
  await page.locator("#wizard-next").click();
  await expect(page.locator("#wizard-raw-access")).toContainText("服务端自动分配");
  await page.locator("#wizard-next").click();
  const request=page.waitForRequest(r=>r.method()==="POST"&&r.url().endsWith("/local/connections"));
  await page.locator("#save").click();
  const body=(await request).postDataJSON();
  expect(body.proxy_type).toBe("tcp");expect(body.application_protocol).toBe("rtsp");
  expect(body.local_port).toBe(554);expect(body).not.toHaveProperty("remote_port");expect(body).not.toHaveProperty("subdomain");
});

test("old servers explain the upgrade and retain HTTP creation", async ({page}) => {
  await services(page,undefined);
  await page.locator("#add").click();await page.locator("#protocol").selectOption("tcp");
  await expect(page.locator("#transport-note")).toContainText("升级服务端至 7.0.0");await expect(page.locator("#wizard-next")).toBeDisabled();
  await page.locator("#protocol").selectOption("http");await expect(page.locator("#wizard-next")).toBeEnabled();
  await page.locator("#name").fill("Web service"); await page.locator("#wizard-next").click();
  await expect(page.locator("#wizard-target")).toBeVisible();
});

test("transport deployment and user permission failures are explained separately", async ({page}) => {
  await services(page,{supported:true,tcp:{enabled:true,can_create:false},udp:{enabled:false,can_create:false}});
  await page.locator("#add").click();await page.locator("#protocol").selectOption("ssh");
  await expect(page.locator("#port")).toHaveValue("22");await expect(page.locator("#transport-note")).toContainText("尚未允许普通用户");await expect(page.locator("#wizard-next")).toBeDisabled();
  await page.locator("#protocol").selectOption("udp");await expect(page.locator("#transport-note")).toContainText("未开放此传输类型");
});

test("service templates supply local defaults while preserving the user's service name", async ({ page }) => {
  await services(page, { supported: true, tcp: { enabled: true, can_create: true }, udp: { enabled: true, can_create: true } });
  await page.locator("#add").click();
  for (const [template, port, scheme] of [["nas", 5000, "http"], ["homeassistant", 8123, "http"], ["immich", 2283, "http"], ["jellyfin", 8096, "http"], ["https", 443, "https"], ["ssh", 22, "http"], ["rdp", 3389, "http"], ["rtsp", 554, "http"], ["udp", 51820, "http"]]) {
    await page.locator("#protocol").selectOption(template);
    await expect(page.locator("#port")).toHaveValue(String(port));
    await expect(page.locator("#scheme")).toHaveValue(scheme);
  }
  await page.locator("#name").fill("My private service");
  await page.locator("#protocol").selectOption("nas");
  await page.locator("#sidebar-locale").click();
  await expect(page.locator("#name")).toHaveValue("My private service");
  await page.locator("#wizard-next").click();
  await expect(page.locator("#host")).toHaveValue("127.0.0.1");
  await expect(page.locator("#wizard-next")).toBeDisabled();
});

test("publishing waits for a checked target and shows the actual address and synchronization state", async ({ page }) => {
  await services(page, undefined);
  const probes = [], writes = [];
  const connection = { id: "created-service", name: "Photos", proxy_type: "http", public_url: "https://photos.example.test", enabled: true, version: 3, applied_version: 2, state: "Online" };
  await page.route("**/local/connection-check", route => { probes.push(route.request().postDataJSON()); return route.fulfill({ json: { status: "pass", code: "TARGET_HTTP_READY" } }); });
  await page.route("**/local/connections", route => {
    if (route.request().method() === "POST") { writes.push(route.request().postDataJSON()); return route.fulfill({ json: connection }); }
    return route.fulfill({ json: { items: [{ ...connection, applied_version: 3 }] } });
  });
  await page.locator("#add").click();
  await page.locator("#protocol").selectOption("immich");
  await page.locator("#name").fill("Photos");
  await page.locator("#name").press("Enter");
  await expect(page.locator("#wizard-target")).toBeVisible();
  expect(writes).toHaveLength(0);
  await page.locator("#target-check").click();
  await expect(page.locator("#wizard-next")).toBeEnabled();
  expect(probes[0]).toEqual({ proxy_type: "http", local_host: "127.0.0.1", local_port: 2283, local_scheme: "http" });
  await page.locator("#wizard-next").click();
  await page.locator("#subdomain").fill("photos");
  await page.locator("#wizard-next").click();
  await expect(page.locator("#wizard-summary")).toContainText("2283");
  expect(writes).toHaveLength(0);
  await page.locator("#save").click();
  await expect(page.locator("#wizard-address")).toHaveValue(connection.public_url);
  await expect(page.locator("#wizard-result-state")).toContainText("等待设备同步");
  expect(writes).toHaveLength(1);
  expect(writes[0]).not.toHaveProperty("remote_port");
  await page.locator("#wizard-refresh").click();
  await expect(page.locator("#wizard-result-state")).toContainText("设备已应用配置");
  await expect(page.locator("#save")).toBeHidden();
});

test("UDP requires explicit acknowledgement and a changed target discards stale probe results", async ({ page }) => {
  await services(page, { supported: true, udp: { enabled: true, can_create: true } });
  let release, pending = false;
  await page.route("**/local/connection-check", async route => {
    pending = true;
    await new Promise(resolve => { release = resolve; });
    await route.fulfill({ json: { status: "manual", code: "UDP_MANUAL_CHECK" } }).catch(() => {});
  });
  await page.locator("#add").click(); await page.locator("#protocol").selectOption("udp");
  await page.locator("#name").fill("Private UDP"); await page.locator("#wizard-next").click();
  await page.locator("#target-check").click();
  await expect.poll(() => pending).toBe(true);
  await page.locator("#host").fill("192.168.1.3"); release();
  await expect(page.locator("#target-check")).toBeEnabled();
  await expect(page.locator("#target-result")).toBeEmpty();
  await expect(page.locator("#wizard-next")).toBeDisabled();
  await page.unroute("**/local/connection-check");
  await page.route("**/local/connection-check", route => route.fulfill({ json: { status: "manual", code: "UDP_MANUAL_CHECK" } }));
  await page.locator("#target-check").click();
  await expect(page.locator("#target-result")).toContainText("无法通过打开端口证明可达");
  await expect(page.locator("#wizard-next")).toBeDisabled();
  await page.locator("#target-ack").check();
  await expect(page.locator("#wizard-next")).toBeEnabled();
  await page.locator("#port").fill("51821");
  await expect(page.locator("#wizard-next")).toBeDisabled();
});

test("an unreachable target offers a retry and a publish error retains the complete draft", async ({ page }) => {
  await services(page, undefined);
  let targetReady = false;
  await page.route("**/local/connection-check", route => route.fulfill({ json: { status: targetReady ? "pass" : "fail", code: targetReady ? "TARGET_HTTP_READY" : "TARGET_UNREACHABLE" } }));
  await page.route("**/local/connections", route => route.fulfill({ status: 503, json: { message: "Service temporarily unavailable" } }));
  await page.locator("#add").click(); await page.locator("#protocol").selectOption("jellyfin");
  await page.locator("#wizard-next").click(); await page.locator("#target-check").click();
  await expect(page.locator("#target-result")).toContainText("本地端口不可达");
  await expect(page.locator("#wizard-next")).toBeDisabled();
  targetReady = true; await page.locator("#target-check").click();
  await page.locator("#wizard-next").click(); await page.locator("#subdomain").fill("movies");
  await page.locator("#wizard-next").click(); await page.locator("#save").click();
  await expect(page.locator("#edit-error")).toContainText("Service temporarily unavailable");
  await expect(page.locator("#wizard-summary")).toContainText("Jellyfin");
  await expect(page.locator("#wizard-summary")).toContainText("movies");
  await expect(page.locator("#wizard-summary")).toContainText("8096");
  await expect(page.locator("#wizard-result")).toBeHidden();
  await expect(page.locator("#save")).toBeEnabled();
});

test("an existing RTSP connection keeps its URI and remains editable after self-service is disabled", async ({page}) => {
  const item={id:"camera",name:"Camera",proxy_type:"tcp",application_protocol:"rtsp",public_endpoint:"camera.example:12000",access_url:"rtsp://camera.example:12000",local_scheme:"http",local_host:"127.0.0.1",local_port:554,enabled:true,version:3,subdomain:"generated-camera"};
  await services(page,{supported:true,tcp:{enabled:true,can_create:false}},[item]);
  await expect(page.locator(".url")).toHaveText("rtsp://camera.example:12000");
  await page.locator('[data-edit="camera"]').click();await expect(page.locator("#protocol")).toHaveValue("rtsp");
  await expect(page.locator("#protocol")).toBeDisabled();await expect(page.locator("#save")).toBeEnabled();await expect(page.locator("#subdomain")).not.toBeVisible();
});

test("tunnel table keeps real targets and prototype-style action icons", async ({page}) => {
  const item={id:"service-one",name:"Family photos",proxy_type:"http",application_protocol:"http",public_url:"https://photos.example.test",local_host:"127.0.0.1",local_port:3000,enabled:true,state:"Online",version:1};
  await services(page,undefined,[item]);
  await expect(page.locator(".service-list-head")).toContainText("公网地址");
  await expect(page.locator(".service-target")).toHaveText("127.0.0.1:3000");
  await expect(page.locator(".service-row .actions svg")).toHaveCount(4);
  await expect(page.locator(".service-row .url")).toHaveText(item.public_url);
  await expect(page.locator(".filter-bar svg")).toHaveCount(2);
  await expect(page.locator("#add svg")).toHaveCount(1);
  await page.route("**/local/connections/service-one", route => route.fulfill({status:500,json:{message:"Temporary failure"}}));
  await page.locator('[data-toggle="service-one"]').click();
  await expect(page.locator("#status")).toContainText("Temporary failure");
  await expect(page.locator('[data-toggle="service-one"] svg')).toHaveCount(1);
});

test("a slow device request cannot restore an old navigation highlight", async ({page}) => {
  let delayNext = false;
  await page.route("**/local/state", async route => {
    if (delayNext) { delayNext = false; await new Promise(resolve => setTimeout(resolve, 300)); }
    await route.fulfill({json:{enrolled:true,agent_state:"Online",connections:[]}});
  });
  await page.route("**/local/update", route => route.fulfill({json:{newer:false}}));
  await page.route("**/local/devices", route => route.fulfill({json:{local_device_id:"local",items:[]}}));
  await page.reload();
  await expect(page.locator("#remote-page")).toBeVisible();
  delayNext = true;
  await page.locator("#nav-devices").click();
  await page.locator("#nav-tunnels").click();
  await expect(page.locator("#home")).toBeVisible();
  await page.waitForTimeout(350);
  await expect(page.locator(".sidebar-nav button.active")).toHaveCount(1);
  await expect(page.locator("#nav-tunnels")).toHaveClass(/active/);
});

test("settings show the installed version without inventing a release", async ({page}) => {
  await services(page,undefined);
  await page.route("**/local/update", route => route.fulfill({json:{current:"8.0.0",newer:false}}));
  await page.locator("#nav-settings").click();
  await expect(page.locator("#update-version-badge")).toHaveText("8.0.0");
  await expect(page.locator("#update-page-status")).toContainText("当前没有更新的正式版本");
  await expect(page.locator(".update-logo svg")).toHaveCount(1);
  await expect(page.locator(".nav-update-dot")).toBeHidden();
  await page.route("**/local/update", route => route.fulfill({json:{current:"8.0.0",latest:"8.2.0",newer:true,url:"https://github.com/ZHanry/home-tunnel-client/releases/tag/8.2.0"}}));
  await page.locator("#update-check").click();
  await expect(page.locator(".nav-update-dot")).toBeVisible();
  await expect(page.locator("#nav-settings")).toHaveAttribute("aria-label", /8\.2\.0/);
});

test("desktop login fields have names and theme uses a readable button foreground", async ({
  page,
}) => {
  for (const id of ["server", "username", "password", "new-password", "confirm-password"])
    expect(await page.locator(`#${id}`).evaluate((el) => el.labels.length)).toBe(1);
  await page.locator("#theme-toggle").click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  expect(await page.locator("#login-button").evaluate((el) => getComputedStyle(el).color)).toBe(
    "rgb(36, 34, 87)",
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
  await expect(page.locator("#remote-page")).toBeVisible();
  await page.route("**/local/logout", (route) =>
    route.fulfill({ status: 500, json: { message: "退出失败，请重试" } }),
  );
  page.on("dialog", (dialog) => dialog.accept());
  await page.locator("#nav-settings").click();
  await page.locator("#logout").click();
  await expect(page.locator("#settings-error")).toContainText("退出失败");
  await expect(page.locator("#logout")).toBeEnabled();
});

test("the web console opens through the default-browser endpoint, not a window", async ({ page }) => {
  await page.route("**/local/state", route => route.fulfill({json:{enrolled:true,agent_state:"Online",console_url:"https://server.example",connections:[]}}));
  await page.route("**/local/devices", route => route.fulfill({json:{local_device_id:"local",items:[]}}));
  await page.route("**/local/update", route => route.fulfill({json:{newer:false}}));
  const requests = [];
  let failure = false;
  await page.route("**/local/console/open", route => {
    requests.push(route.request().postDataJSON());
    return failure ? route.fulfill({status:503,json:{message:"无法打开默认浏览器"}}) : route.fulfill({json:{ok:true}});
  });
  await page.reload();
  await page.evaluate(() => { window.open = (...args) => { window.opened = args; return null; }; });
  await expect(page.locator("#remote-page")).toBeVisible();
  await page.locator("#nav-console").click();
  await expect.poll(() => requests.length).toBe(1);
  await page.locator("#remote-open-console").click();
  await expect.poll(() => requests.length).toBe(2);
  expect(requests).toEqual([{}, {section:"remote"}]);
  // The page never supplies the address; Go derives it from the signed-in server.
  expect(requests.every(body => !("url" in body))).toBe(true);
  failure = true;
  await page.locator("#remote-open-console").click();
  await expect(page.locator("#remote-open-error")).toContainText("无法打开默认浏览器");
  expect(await page.evaluate(() => window.opened)).toBeUndefined();
});

test("scrollbars are hidden while pages keep wheel and keyboard scrolling", async ({ page }) => {
  await page.setViewportSize({ width: 1100, height: 720 });
  const connections = Array.from({length:14}, (_, index) => ({id:`service-${index}`,name:`Service ${index}`,proxy_type:"http",public_url:`https://s${index}.example.test`,local_host:"127.0.0.1",local_port:3000+index,enabled:true,state:"Online",version:1}));
  await services(page, undefined, connections);
  const styles = await page.evaluate(() => ["html", "body", ".app-sidebar", "main", ".service-list"].map(selector => getComputedStyle(document.querySelector(selector)).scrollbarWidth));
  expect(styles).toEqual(["none", "none", "none", "none", "none"]);
  // No gutter is reserved, yet the document is taller than the window.
  expect(await page.evaluate(() => window.innerWidth - document.documentElement.clientWidth)).toBe(0);
  expect(await page.evaluate(() => document.documentElement.scrollHeight > document.documentElement.clientHeight)).toBe(true);
  await page.mouse.move(600, 400);
  await page.mouse.wheel(0, 400);
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(0);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.locator("#service-search").focus();
  await page.locator("#service-search").evaluate(element => element.blur());
  await page.keyboard.press("End");
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(0);
});

test("spacious sign-in stays usable in short, narrow and MFA recovery windows", async ({ page }) => {
  for (const [width, height] of [[390, 600], [944, 600], [1100, 720], [1280, 800], [1440, 960]]) {
    await page.setViewportSize({ width, height });
    for (const reveal of [[], ["mfa-step"], ["mfa-step", "password-change"]]) {
      await page.evaluate(ids => ids.forEach(id => document.getElementById(id).classList.remove("hidden")), reveal);
      const sizes = await page.evaluate(() => ({ width:document.documentElement.clientWidth, scrollWidth:document.documentElement.scrollWidth, input:document.getElementById("server").getBoundingClientRect().toJSON(), password:document.getElementById("password").getBoundingClientRect().toJSON(), overflow:getComputedStyle(document.body).overflowY }));
      expect(sizes.scrollWidth).toBeLessThanOrEqual(sizes.width);
      expect(sizes.input.height).toBeGreaterThanOrEqual(48);
      expect(sizes.input.width).toBeGreaterThanOrEqual(230);
      expect(sizes.password.width).toBeGreaterThanOrEqual(170);
      expect(sizes.overflow).toBe("auto");
      await page.locator("#login-button").scrollIntoViewIfNeeded();
      await expect(page.locator("#login-button")).toBeInViewport();
      if (reveal.includes("password-change")) { await page.locator("#confirm-password").scrollIntoViewIfNeeded(); await expect(page.locator("#confirm-password")).toBeInViewport(); }
    }
    await page.evaluate(() => ["mfa-step", "password-change"].forEach(id => document.getElementById(id).classList.add("hidden")));
  }
  await page.locator("#login-button").focus();
  await expect(page.locator("#login-button")).toBeFocused();
});

async function enrolledDevices(page) {
  const current = {id:"local", name:"This workstation", status:"active", online:true};
  const peer = {id:"peer", name:"Other workstation", status:"active", online:true};
  await page.route("**/local/state", route => route.fulfill({json:{enrolled:true,console_url:"https://console.example.test",device_name:current.name,version:"10.1.0",connections:[]}}));
  await page.route("**/local/devices", route => route.fulfill({json:{local_device_id:current.id,items:[current,peer]}}));
  await page.route("**/local/update", route => route.fulfill({json:{current:"10.1.0",newer:false}}));
  await page.route("**/local/remote/state", route => route.fulfill({json:{enrolled:true,enabled:true,running:true,capabilities:{available:true},access_profile:{device_id:"482913570"},pending:[],grants:[]}}));
  await page.reload();
  await expect(page.locator("#remote-page")).toBeVisible();
  return {current,peer};
}

test("current device renames once, preserves failed drafts, and survives reload", async ({page}) => {
  const {current} = await enrolledDevices(page);
  let fail = true, requests = [], release;
  await page.route("**/local/device/name", async route => {
    const body = route.request().postDataJSON(); requests.push(body);
    if (fail) return route.fulfill({status:503,json:{message:"Rename temporarily unavailable"}});
    await new Promise(resolve => {release=resolve;});
    current.name = body.name;
    return route.fulfill({json:{device_name:current.name}});
  });
  await page.locator("#nav-devices").click();
  const local = page.locator(".account-device-card").filter({hasText:"This workstation"});
  await expect(local.getByRole("button",{name:"远程控制",exact:true})).toHaveCount(0);
  await local.getByRole("button",{name:"重命名本机"}).click();
  await expect(page.locator("#device-name")).toHaveValue(current.name);
  await page.locator("#device-name").fill("  Studio <one>  ");
  await page.locator("#device-rename-save").click();
  await expect(page.locator("#device-rename-error")).toHaveText("Rename temporarily unavailable");
  await expect(page.locator("#device-name")).toHaveValue("  Studio <one>  ");
  fail=false;
  await page.locator("#device-rename-save").click();
  await expect.poll(()=>requests.length).toBe(2);
  await page.locator("#device-name").press("Enter");
  expect(requests).toEqual([{name:"Studio <one>"},{name:"Studio <one>"}]);
  release();
  await expect(page.locator("#device-rename")).not.toBeVisible();
  await expect(page.locator("#sidebar-machine")).toHaveText("Studio <one>");
  await expect(page.locator("#devices-list [data-no-translate]").first()).toHaveText("Studio <one>");
  await expect(page.locator("#devices-list one")).toHaveCount(0);
  await page.reload();
  await expect(page.locator("#sidebar-machine")).toHaveText("Studio <one>");
  await page.locator("#nav-devices").click();
  await page.getByRole("button",{name:"重命名本机"}).click();
  await expect(page.locator("#device-name")).toHaveValue("Studio <one>");
});

test("rename Cancel, Escape and navigation discard drafts without changing names", async ({page}) => {
  await enrolledDevices(page);
  let changes=0;
  await page.route("**/local/device/name", route => { ++changes; return route.fulfill({json:{device_name:"unexpected"}}); });
  await page.locator("#nav-devices").click();
  for (const dismiss of ["cancel", "escape", "navigate"]) {
    await page.getByRole("button",{name:"重命名本机"}).click();
    await page.locator("#device-name").fill("Abandoned draft");
    if (dismiss === "cancel") await page.locator("#device-rename-cancel").click();
    else if (dismiss === "escape") await page.keyboard.press("Escape");
    else await page.evaluate(()=>document.getElementById("nav-settings").click());
    await expect(page.locator("#device-rename")).not.toBeVisible();
    if (dismiss === "navigate") await page.locator("#nav-devices").click();
    await page.getByRole("button",{name:"重命名本机"}).click();
    await expect(page.locator("#device-name")).toHaveValue("This workstation");
    await page.locator("#device-rename-cancel").click();
  }
  expect(changes).toBe(0);
});

test("closing a pending rename never reopens the modal or redirects a newer page", async ({page}) => {
  const {current}=await enrolledDevices(page);
  let release;
  await page.route("**/local/device/name",async route=>{
    await new Promise(resolve=>{release=resolve;}); current.name="Saved during close";
    await route.fulfill({json:{device_name:current.name}});
  });
  await page.locator("#nav-devices").click();
  await page.getByRole("button",{name:"重命名本机"}).click();
  await page.locator("#device-name").fill("Saved during close");
  await page.locator("#device-rename-save").click();
  await expect.poll(()=>!!release).toBe(true);
  await page.locator("#device-rename-cancel").click();
  await page.locator("#nav-settings").click();
  release();
  await expect(page.locator("#sidebar-machine")).toHaveText("Saved during close");
  await expect(page.locator("#settings")).toBeVisible();
  await expect(page.locator("#device-rename")).not.toBeVisible();
  await expect(page.locator("#nav-settings")).toHaveClass(/active/);
});

test("manual local device and access IDs never open a self remote session", async ({page}) => {
  await enrolledDevices(page);
  await expect(page.locator("#rd-host-code")).toHaveText("482 913 570");
  const opened=[];
  await page.route("**/local/remote/window",route=>{opened.push(route.request().postDataJSON());return route.fulfill({json:{ok:true}});});
  for (const id of ["local", "LOCAL", "482 913-570"]) {
    await page.locator("#remote-device-id").fill(id);
    await page.locator("#remote-connect-form button").click();
    await expect(page.locator("#remote-open-error")).toHaveText("不能远程连接本机，请选择其他设备。");
  }
  expect(opened).toHaveLength(0);
  await page.locator("#remote-device-id").fill("peer");
  await page.locator("#remote-connect-form button").click();
  await expect.poll(()=>opened).toEqual([{device_id:"peer"}]);
});

test("a delayed Settings load cannot pull the user away from newer navigation", async ({page}) => {
  await enrolledDevices(page);
  let release, delayed=false;
  await page.route("**/local/state",async route=>{
    if(!delayed){delayed=true;await new Promise(resolve=>{release=resolve;});}
    await route.fulfill({json:{enrolled:true,console_url:"https://console.example.test",device_name:"This workstation",connections:[]}});
  });
  await page.locator("#nav-settings").click();
  await expect.poll(()=>!!release).toBe(true);
  await page.locator("#nav-devices").click();
  await expect(page.locator("#devices-page")).toBeVisible();
  release();
  await expect(page.locator("#nav-devices")).toHaveClass(/active/);
  await expect(page.locator("#settings")).toBeHidden();
  await page.locator("#nav-settings").click();
  await expect(page.locator("#settings-server")).toHaveText("https://console.example.test");
  await expect(page.locator("#settings")).toBeVisible();
});
