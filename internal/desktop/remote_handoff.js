(function (launch) {
  "use strict";
  if (window.top !== window || location.origin !== launch.origin || location.pathname !== "/admin") return;
  Object.defineProperty(window, "__htNativeRemoteWindow", { value: true, writable: false, configurable: false });
  Object.defineProperty(window, "__htNativeRemoteWindowID", { value: launch.window_id, writable: false, configurable: false });
  const ready = (async () => {
    if (location.href !== launch.url) return false;
    const options = { headers: { "x-native-window-id": launch.window_id }, credentials: "same-origin", redirect: "error", cache: "no-store", signal: AbortSignal.timeout(15000) };
    let existing = await fetch("/api/v1/auth/session", options);
    if (existing.status === 401) {
      const refreshed = await fetch("/api/v1/auth/refresh", { ...options, method: "POST", headers: { ...options.headers, "content-type": "application/json" }, body: JSON.stringify({ client_type: "web" }) });
      if (refreshed.ok) existing = await fetch("/api/v1/auth/session", options);
      else if (refreshed.status !== 401 && refreshed.status !== 403) return false;
    }
    if (existing.ok && (await existing.json()).native_window_id === launch.window_id) return true;
    if (!existing.ok && existing.status !== 401 && existing.status !== 403) return false;
    const result = await fetch("/api/v1/auth/native-remote-handoff/redeem", { ...options, method: "POST", headers: { ...options.headers, "content-type": "application/json" }, body: JSON.stringify({ code: launch.code }) });
    return result.ok;
  })().catch(() => false);
  Object.defineProperty(window, "__htNativeRemoteReady", { value: ready, writable: false, configurable: false });
})
