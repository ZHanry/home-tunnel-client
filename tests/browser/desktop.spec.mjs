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

test("remote backend stays unavailable and enrollment requires explicit server trust", async ({page}) => {
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#nav-remote").click();
  await expect(page.locator("#rd-host-status")).toContainText("没有可用的远控后端");
  await expect(page.locator("#rd-host-enable")).toBeDisabled();
  await expect(page.locator("#rd-host-enroll")).toBeHidden();
  await page.route("**/local/remote/state",route=>route.fulfill({json:{enrolled:false,enabled:false,capabilities:{available:true,permissions:["view"]},pending:[],grants:[]}}));
  await page.route("**/local/remote/trust",route=>route.fulfill({json:{origin:"https://server.example",server_instance_id:"server-one",active_kid:"public-key",trust_pin:"a".repeat(64)}}));
  await page.evaluate(()=>refreshRemoteHost());
  await expect(page.locator("#rd-host-enroll")).toBeVisible();
  await page.locator("#rd-host-user").fill("alice"); await page.locator("#rd-host-password").fill("temporary-password");
  await expect(page.locator("#rd-host-enroll-submit")).toBeDisabled();
  await page.locator("#rd-host-trust-load").click();
  await expect(page.locator("#rd-host-trust")).toContainText("https://server.example");
  await expect(page.locator("#rd-host-enroll-submit")).toBeDisabled();
  await page.locator("#rd-host-trust-confirm").check();
  await expect(page.locator("#rd-host-mfa")).toBeHidden();
  const attempts=[];
  await page.route("**/local/remote/action",route=>{
    attempts.push(route.request().postDataJSON());
    return attempts.length===1
      ? route.fulfill({status:401,json:{error_code:"RD_MFA_REQUIRED",message:"Dynamic code required"}})
      : route.fulfill({json:{ok:true}});
  });
  await page.locator("#rd-host-enroll-submit").click();
  await expect(page.locator("#rd-host-mfa")).toBeVisible();
  expect(attempts[0].mfa_code).toBe("");
  await page.locator("#rd-host-password").fill("temporary-password");
  await page.locator("#rd-host-mfa").fill("123456");
  await page.locator("#rd-host-enroll-submit").click();
  await expect.poll(()=>attempts.length).toBe(2);
  expect(attempts[1].action).toBe("enroll");
  expect(attempts[1].trust_pin).toBe("a".repeat(64));
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
  await page.locator("#rd-host-pending").getByRole("button",{name:"允许以上权限 / Allow listed permissions"}).click();
  await expect.poll(()=>action?.action).toBe("approve");
  expect(action.permissions).toEqual(event.permissions);
  await expect(page.locator("#rd-host-pending")).toContainText("123456");
  await expect(page.locator("#rd-host-pending button")).toHaveCount(0);
});

test("unattended controls stay unavailable without a native service and can revoke local trust", async ({page}) => {
  const state = {enrolled:true,enabled:true,running:true,unattended_enabled:false,capabilities:{available:true,unattended_enabled:false},pending:[],grants:[]};
  const actions = [];
  await page.route("**/local/remote/state",route=>route.fulfill({json:state}));
  await page.route("**/local/remote/action",route=>{
    const action=route.request().postDataJSON().action;actions.push(action);
    state.unattended_enabled=action==="enable_unattended";
    return route.fulfill({json:{ok:true}});
  });
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#nav-remote").click();
  await page.locator('[data-remote-tab="unattended"]').click();
  await expect(page.locator("#rd-unattended-enable")).toBeDisabled();
  await expect(page.locator("#rd-unattended-detail")).toContainText("固定密码仅作用于已登录的桌面");
  state.capabilities.unattended_enabled=true;
  await page.evaluate(()=>refreshRemoteHost());
  await expect(page.locator("#rd-unattended-enable")).toBeEnabled();
  await page.locator("#rd-unattended-enable").click();
  await expect(page.locator("#rd-unattended-status")).toHaveText("已开启");
  await page.locator("#rd-unattended-disable").click();
  await expect(page.locator("#rd-unattended-status")).toHaveText("未启用");
  expect(actions).toEqual(["enable_unattended","disable_unattended"]);
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
  await page.locator('[data-remote-tab="unattended"]').click();
  await expect(page.locator("#rd-access-device-id")).toHaveText("123456789");
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
  await page.locator('[data-remote-tab="unattended"]').click();
  await expect(page.locator("#rd-fixed-password")).toHaveValue("");
});

test("temporary assistance shows its password once and retains revocation after reload", async ({ page }) => {
  const invite = { id: "invite-one", device_id: "123456789", temporary_password: "ABcd2345EFgh", expires_at: new Date(Date.now() + 300000).toISOString() };
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
  await page.getByRole("button",{name:"选择保存位置 / Choose destination"}).click();
  await expect.poll(()=>actions.length).toBe(1);
  expect(actions[0]).toEqual({action:"receive",id:"file-one",session_id:"session-file",connection_epoch:3});
  await page.getByRole("button",{name:"选择多个文件发送 / Select files to send"}).click();
  await expect.poll(()=>actions.length).toBe(2);
  expect(actions[1]).toEqual({action:"send",session_id:"session-file",connection_epoch:3});
  files.items[0]={...files.items[0],event:"error",may_be_saved:true,error_code:"RD_FILE_CANCELLED"};
  await page.evaluate(()=>refreshRemoteHost());
  await expect(page.locator("#rd-host-files")).toContainText("文件可能已保存");
  await expect(page.getByRole("button",{name:"选择保存位置 / Choose destination"})).toHaveCount(0);
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

test("device tags use a version and retain the draft on conflict", async ({page}) => {
  await services(page,undefined);
  let body;
  await page.route("**/local/device/metadata",route=>{
    if(route.request().method()==="PATCH") {body=route.request().postDataJSON();return route.fulfill({status:409,json:{message:"Metadata changed; refresh before retrying"}});}
    return route.fulfill({json:{id:"local",tags:["home"],favorite:false,metadata_version:4}});
  });
  await page.locator("#nav-settings").click();
  await expect(page.locator("#device-tags")).toHaveValue("home");
  await page.locator("#device-tags").fill("home, nas");await page.locator("#device-favorite").check();
  await page.locator("#metadata-save").click();
  await expect(page.locator("#settings-error")).toContainText("Metadata changed");
  await expect(page.locator("#device-tags")).toHaveValue("home, nas");
  expect(body).toEqual({tags:["home","nas"],favorite:true,expected_metadata_version:4});
});

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
  await expect(page.locator("#transport-note")).toContainText("升级服务端至 7.0.0");await expect(page.locator("#save")).toBeDisabled();
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

test("updates page shows the installed version without inventing a release", async ({page}) => {
  await services(page,undefined);
  await page.route("**/local/update", route => route.fulfill({json:{current:"8.0.0",newer:false}}));
  await page.locator("#nav-updates").click();
  await expect(page.locator("#update-version-badge")).toHaveText("8.0.0");
  await expect(page.locator("#update-page-status")).toContainText("当前没有更新的正式版本");
  await expect(page.locator(".update-logo svg")).toHaveCount(1);
  await expect(page.locator(".nav-update-dot")).toBeHidden();
  await page.route("**/local/update", route => route.fulfill({json:{current:"8.0.0",latest:"8.2.0",newer:true,url:"https://github.com/ZHanry/home-tunnel-client/releases/tag/8.2.0"}}));
  await page.locator("#update-check").click();
  await expect(page.locator(".nav-update-dot")).toBeVisible();
  await expect(page.locator("#nav-updates")).toHaveAttribute("aria-label", /8\.2\.0/);
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
