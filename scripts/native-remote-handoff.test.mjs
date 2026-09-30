import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../internal/desktop/remote_handoff.js", import.meta.url), "utf8");
const launch = { origin: "https://console.example.test", url: "https://console.example.test/admin?nativeRemote=1#remote", code: "S".repeat(43), window_id: "12345678-1234-1234-1234-123456789abc" };
async function run(responses, { url = launch.url, frame = false } = {}) {
  const requests = [], window = {}, location = new URL(url);
  window.top = frame ? {} : window;
  const context = vm.createContext({ window, location, AbortSignal, fetch: async (url, options) => {
    requests.push({ url, options });
    const next = responses.shift(); assert.ok(next, "unexpected request");
    if (next instanceof Error) throw next;
    return { status: next.status, ok: next.status >= 200 && next.status < 300, json: async () => next.data };
  } });
  vm.runInContext(`${source}(${JSON.stringify(launch)});`, context);
  const ready = await window.__htNativeRemoteReady;
  return { requests, ready, window };
}
test("single-use code is a same-origin POST body, never a URL or global", async () => {
  const result = await run([{ status: 401 }, { status: 401 }, { status: 200 }]);
  assert.equal(result.ready, true);
  assert.equal(result.requests.length, 3);
  assert.deepEqual(Object.keys(result.window).sort(), ["top"]);
  for (const { url, options } of result.requests) {
    assert.ok(!url.includes(launch.code)); assert.ok(url.startsWith("/api/v1/auth/"));
    assert.equal(options.redirect, "error"); assert.equal(options.credentials, "same-origin");
  }
  assert.equal(JSON.parse(result.requests.at(-1).options.body).code, launch.code);
});
test("reload/back reuses only exact originating window session without replay", async () => {
  const result = await run([{ status: 200, data: { native_window_id: launch.window_id } }]);
  assert.equal(result.ready, true); assert.equal(result.requests.length, 1);
});
test("expired access refreshes then rechecks the window binding", async () => {
  const result = await run([{ status: 401 }, { status: 200 }, { status: 200, data: { native_window_id: launch.window_id } }]);
  assert.equal(result.ready, true); assert.equal(result.requests.length, 3);
  assert.ok(!result.requests.some(request => request.url.endsWith("/redeem")));
});
test("ordinary or other-window sessions must redeem, not silently switch identity", async () => {
  for (const data of [{}, { native_window_id: "another-window" }]) {
    const result = await run([{ status: 200, data }, { status: 401 }]);
    assert.equal(result.ready, false); assert.equal(result.requests.length, 2);
  }
});
test("hostile origin/path/frame never receives authorization; changed query fails closed", async () => {
  for (const options of [{ url: "https://attacker.test/admin" }, { url: "https://console.example.test.attacker.test/admin" }, { url: "https://console.example.test/other" }, { frame: true }, { url: "https://console.example.test/admin?other=1#remote" }]) {
    const result = await run([], options); assert.equal(result.requests.length, 0); assert.notEqual(result.ready, true);
  }
});
test("network/server failures do not redeem or fall back to another login", async () => {
  for (const responses of [[{ status: 503 }], [new Error("network")], [{ status: 401 }, { status: 503 }]]) {
    const result = await run(responses); assert.equal(result.ready, false); assert.ok(!result.requests.some(request => request.url.endsWith("/redeem")));
  }
});
