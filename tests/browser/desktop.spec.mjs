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
  await page.route("**/local/remote/state", route => route.fulfill({json:{enrolled:false,enabled:false,capabilities:{available:false},pending:[],grants:[]}}));
  await page.goto("/desktop-preview");
});

test("remote backend stays unavailable and enrollment requires explicit server trust", async ({page}) => {
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#settings-open").click();
  await expect(page.locator("#rd-host-status")).toContainText("暂未提供");
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
  let enrollment;
  await page.route("**/local/remote/action",route=>{enrollment=route.request().postDataJSON();return route.fulfill({json:{ok:true}});});
  await page.locator("#rd-host-enroll-submit").click();
  await expect.poll(()=>enrollment?.action).toBe("enroll");
  expect(enrollment.trust_pin).toBe("a".repeat(64));
  await expect(page.locator("#rd-host-password")).toHaveValue("");
});

test("local approval lists every requested permission and pairing code cannot grant twice", async ({page}) => {
  const event={kind:"pairing",id:"pair-one",controller_endpoint_id:"controller-a",controller_thumbprint:"public-fingerprint",permissions:["view","audio.microphone","files.send"],mode:"one_session"};
  await page.route("**/local/remote/state",route=>route.fulfill({json:{enrolled:true,enabled:true,running:true,capabilities:{available:true},pending:[event],grants:[]}}));
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#settings-open").click();
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

test("session files request local selection with the displayed epoch and render names as text", async ({page}) => {
  const files = {session_id:"session-file",connection_epoch:3,can_send:true,can_receive:true,items:[{event:"offer",id:"file-one",name:"<img src=x onerror=alert(1)>.txt",size:24,outgoing:false}]};
  await page.route("**/local/remote/state",route=>route.fulfill({json:{enrolled:true,enabled:true,running:true,capabilities:{available:true},pending:[],grants:[],files}}));
  await services(page,undefined);
  await page.route("**/local/device/metadata",route=>route.fulfill({json:{tags:[],metadata_version:1}}));
  await page.locator("#settings-open").click();
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
  await page.locator("#settings-open").click();
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
