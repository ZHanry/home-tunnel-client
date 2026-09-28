(() => {
  "use strict";
  // The always-on-top approval popup. It only mirrors /local/remote/state and
  // sends the same /local/remote/action requests as the main window's cards;
  // nothing here decides a request without a click.
  const $ = (id) => document.getElementById(id);
  const messages = {
    "远程控制请求": ["远程控制请求", "Remote control request"],
    "有人请求连接这台电脑": ["有人请求连接这台电脑", "Someone wants to connect to this computer"],
    "配对请求 · 仅本次会话": ["配对请求 · 仅本次会话", "Pairing request · this session only"],
    "长期配对请求": ["长期配对请求", "Long-term pairing request"],
    "会话请求": ["会话请求", "Session request"],
    "请核对配对码": ["请核对配对码", "Compare the pairing code"],
    "远程设备": ["远程设备", "Remote device"],
    "请求权限：": ["请求权限：", "Requested: "],
    "仅允许本次连接，可随时在主界面断开。": ["仅允许本次连接，可随时在主界面断开。", "Allows this connection only. You can disconnect at any time."],
    "本机不再提供长期授权，请让对方改用固定密码连接。": ["本机不再提供长期授权，请让对方改用固定密码连接。", "Long-term access is no longer offered. Ask the other person to connect with the fixed password."],
    "核对码": ["核对码", "Code"],
    "请在控制端核对一致后确认。": ["请在控制端核对一致后确认。", "Confirm on the controller once the codes match."],
    "拒绝": ["拒绝", "Decline"],
    "接受": ["接受", "Accept"],
    "知道了": ["知道了", "Got it"],
    "正在被远程控制": ["正在被远程控制", "This computer is being controlled"],
    "主界面": ["主界面", "Open"],
    "断开": ["断开", "Disconnect"],
    "断开远程控制": ["断开远程控制", "Disconnect remote control"],
    "打开 Home Tunnel 主界面": ["打开 Home Tunnel 主界面", "Open the Home Tunnel window"],
    "另一项操作进行中，请稍后再试": ["另一项操作进行中，请稍后再试", "Another action is in progress. Try again shortly."],
    "请求已失效": ["请求已失效", "The request is no longer valid"],
    "屏幕": ["屏幕", "Screen"], "键盘": ["键盘", "Keyboard"], "鼠标": ["鼠标", "Pointer"], "文字输入": ["文字输入", "Text input"],
    "系统声音": ["系统声音", "System audio"], "麦克风": ["麦克风", "Microphone"], "读取剪贴板": ["读取剪贴板", "Read clipboard"],
    "写入剪贴板": ["写入剪贴板", "Write clipboard"], "发送文件": ["发送文件", "Send files"], "接收文件": ["接收文件", "Receive files"],
  };
  const permissionNames = {
    view: "屏幕", "input.keyboard": "键盘", "input.pointer": "鼠标", "input.text": "文字输入", "audio.system": "系统声音",
    "audio.microphone": "麦克风", "clipboard.read": "读取剪贴板", "clipboard.write": "写入剪贴板", "files.send": "发送文件", "files.receive": "接收文件",
  };
  let locale = document.documentElement.lang === "en" ? "en" : "zh-CN";
  const msg = (key) => messages[key]?.[locale === "en" ? 1 : 0] ?? key;
  const secondsText = (n) => locale === "en" ? `${n}s` : `${n} 秒`;
  const acceptLabel = (who) => locale === "en" ? `Accept the remote control request from ${who}` : `接受 ${who} 的远程控制请求`;
  const rejectLabel = (who) => locale === "en" ? `Decline the remote control request from ${who}` : `拒绝 ${who} 的远程控制请求`;
  const queueText = (n) => locale === "en" ? `${n} more waiting` : `还有 ${n} 个请求等待处理`;
  const remainingLabel = (n) => locale === "en" ? `${n} seconds left` : `剩余 ${n} 秒`;

  // The desktop session travels in the fragment, like the main window; the
  // browser never sends a fragment to the server.
  const localSessionToken = new URLSearchParams(location.hash.slice(1)).get("session") || "";
  async function api(path, options = {}) {
    const response = await fetch(path, { ...options, cache: "no-store", headers: { "content-type": "application/json", ...(localSessionToken ? { authorization: `Bearer ${localSessionToken}` } : {}) } });
    const text = await response.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch (e) {}
    if (!response.ok) {
      const code = data?.error_code;
      throw new Error(code === "RD_ACTION_IN_PROGRESS" ? msg("另一项操作进行中，请稍后再试") : data?.message || text || response.statusText);
    }
    return data;
  }

  const ARM_DELAY = 700;
  let mode = "", state = null, loading = false, pollTimer = 0, tickTimer = 0, busy = false;
  let shownKey = "", armedAt = 0, errorText = "", errorKey = "";
  const firstSeen = new Map(), decided = new Set(), acknowledged = new Set();
  let seenCounter = 0;

  function itemsFrom(current, now) {
    const items = [];
    for (const request of current?.access_requests || []) {
      const expires = Date.parse(request.expires_at);
      if (!request.id || !(expires > now)) continue;
      items.push({ key: "access:" + request.id, type: "access", decidable: true, expires, source: request });
    }
    for (const event of current?.pending || []) {
      const expires = Date.parse(event.expires_at);
      if (!event.id || !(expires > now) || !["pairing", "session", "pairing_display"].includes(event.kind)) continue;
      const decidable = event.kind !== "pairing_display" && !event.display_code;
      items.push({ key: event.kind + ":" + event.id, type: event.kind, decidable, expires, source: event,
        longTerm: event.kind === "pairing" && event.mode === "persistent" });
    }
    return items;
  }

  // Newest first; requests first seen together keep the host's order.
  function visibleItems(now) {
    const items = itemsFrom(state, now);
    const present = new Set(items.map((item) => item.key));
    for (const set of [decided, acknowledged]) for (const key of set) if (!present.has(key)) set.delete(key);
    for (const key of firstSeen.keys()) if (!present.has(key)) firstSeen.delete(key);
    for (const item of items) if (!firstSeen.has(item.key)) firstSeen.set(item.key, ++seenCounter);
    return items.filter((item) => !decided.has(item.key) && !acknowledged.has(item.key))
      .sort((a, b) => firstSeen.get(b.key) - firstSeen.get(a.key));
  }

  function requesterOf(source) {
    return source.requester_name || source.requester_account || msg("远程设备");
  }
  function deviceOf(source) {
    return [source.device_name, source.controller_endpoint_id].filter(Boolean).join(" · ");
  }
  function kindText(item) {
    if (item.type === "access") return msg("有人请求连接这台电脑");
    if (item.type === "session") return msg("会话请求");
    if (!item.decidable) return msg("请核对配对码");
    return item.longTerm ? msg("长期配对请求") : msg("配对请求 · 仅本次会话");
  }

  function render() {
    const now = Date.now();
    const items = mode === "request" ? visibleItems(now) : [];
    const item = items[0];
    lastCount = Math.max(lastCount, items.length);
    $("request").hidden = !item;
    $("session").hidden = !!item || !state?.active_session_id || !mode;
    if (item) renderRequest(item, items.length - 1, now);
    else shownKey = "";
    if (!$("session").hidden) renderSession();
    applyStaticText();
  }

  function renderRequest(item, others, now) {
    if (item.key !== shownKey) {
      // A different request may appear under the cursor; keep the buttons
      // inert briefly so a click meant for the previous one cannot land here.
      shownKey = item.key; armedAt = performance.now() + ARM_DELAY;
      if (errorKey !== item.key) errorText = "";
      setTimeout(updateButtons, ARM_DELAY + 20);
    }
    const source = item.source, who = requesterOf(source);
    $("request-kind").textContent = kindText(item);
    $("request-who").textContent = who;
    $("request-who").title = who;
    $("request-device").textContent = deviceOf(source);
    $("request-device").title = deviceOf(source);
    const scopes = (source.permissions || []).map((name) => msg(permissionNames[name] || name));
    $("request-scopes").textContent = scopes.length ? msg("请求权限：") + scopes.join(" · ") : "";
    $("request-scopes").title = $("request-scopes").textContent;
    const code = source.display_code || "";
    $("request-code").hidden = !code;
    $("request-code-label").textContent = msg("核对码");
    $("request-code-value").textContent = code;
    const note = item.longTerm ? msg("本机不再提供长期授权，请让对方改用固定密码连接。")
      : code ? msg("请在控制端核对一致后确认。")
        : item.type === "access" && !scopes.length ? msg("仅允许本次连接，可随时在主界面断开。") : "";
    $("request-note").hidden = !note;
    $("request-note").textContent = note;
    $("request-queue").textContent = others > 0 ? queueText(others) : "";
    $("request-error").textContent = errorText;
    $("request-accept").hidden = !item.decidable || item.longTerm;
    $("request-reject").hidden = !item.decidable;
    $("request-ack").hidden = item.decidable;
    $("request-accept").setAttribute("aria-label", acceptLabel(who));
    $("request-reject").setAttribute("aria-label", rejectLabel(who));
    renderCountdown(item, now);
    updateButtons();
  }

  function renderCountdown(item, now) {
    const seconds = Math.max(0, Math.ceil((item.expires - now) / 1000));
    const node = $("request-countdown");
    node.textContent = secondsText(seconds);
    node.setAttribute("aria-label", remainingLabel(seconds));
    node.dataset.urgent = String(seconds <= 10);
  }

  function renderSession() {
    const grant = (state.grants || []).find((item) => item.session_id && item.session_id === state.active_session_id);
    const who = grant ? [grant.requester_name, grant.controller_endpoint_id].filter(Boolean).join(" · ") : "";
    $("session-who").textContent = who;
    $("session-who").title = who;
    $("session-who").hidden = !who;
  }

  function applyStaticText() {
    document.documentElement.lang = locale;
    $("request-title").textContent = msg("远程控制请求");
    $("request-accept").textContent = msg("接受");
    $("request-reject").textContent = msg("拒绝");
    $("request-ack").textContent = msg("知道了");
    $("session-title").textContent = msg("正在被远程控制");
    $("session-open").textContent = msg("主界面");
    $("session-open").setAttribute("aria-label", msg("打开 Home Tunnel 主界面"));
    $("session-stop").textContent = msg("断开");
    $("session-stop").setAttribute("aria-label", msg("断开远程控制"));
    document.title = `Home Tunnel · ${msg("远程控制请求")}`;
  }

  function updateButtons() {
    const inert = busy || performance.now() < armedAt;
    for (const id of ["request-accept", "request-reject", "request-ack"]) $(id).disabled = inert;
    $("session-stop").disabled = busy;
  }

  function currentItem() {
    return mode === "request" ? visibleItems(Date.now())[0] : undefined;
  }

  async function run(key, work) {
    busy = true; errorText = ""; errorKey = key; updateButtons();
    try { await work(); }
    catch (failure) { errorText = failure.message || String(failure); }
    finally { busy = false; updateButtons(); await refresh(); }
  }

  async function decide(accept, event) {
    // Only a real click by the user may decide; synthetic clicks are ignored.
    if (!event.isTrusted || busy || performance.now() < armedAt) return;
    const item = currentItem();
    if (!item || !item.decidable || item.key !== shownKey || (accept && item.longTerm)) return;
    await run(item.key, async () => {
      const source = item.source;
      const body = item.type === "access"
        ? { action: accept ? "approve_access_request" : "reject_access_request", id: source.id }
        : { action: accept ? "approve" : "reject", id: source.id, kind: source.kind, permissions: source.permissions, mode: source.mode, connection_epoch: source.connection_epoch, state_version: source.state_version };
      await api("/local/remote/action", { method: "POST", body: JSON.stringify(body) });
      decided.add(item.key);
    });
  }

  $("request-accept").addEventListener("click", (event) => decide(true, event));
  $("request-reject").addEventListener("click", (event) => decide(false, event));
  $("request-ack").addEventListener("click", async (event) => {
    if (!event.isTrusted || busy || performance.now() < armedAt) return;
    const item = currentItem();
    if (!item || item.decidable) return;
    acknowledged.add(item.key);
    render();
    await run(item.key, () => api("/local/remote/popup", { method: "POST", body: JSON.stringify({ action: "acknowledge", key: item.key }) }).catch(() => {}));
  });
  $("session-stop").addEventListener("click", (event) => {
    if (!event.isTrusted || busy) return;
    void run("session", () => api("/local/remote/action", { method: "POST", body: JSON.stringify({ action: "stop" }) }));
  });
  $("session-open").addEventListener("click", () => { api("/local/show", { method: "POST", body: "{}" }).catch(() => {}); });

  // Enter and Esc never decide from the popup; Space or a click on a focused
  // button still works for keyboard users.
  document.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === "Escape" || event.key === "NumpadEnter") {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);

  async function refresh() {
    if (loading || !mode) return;
    loading = true;
    try { state = await api("/local/remote/state"); }
    catch (e) {}
    finally { loading = false; }
    if (mode) render();
  }

  function schedulePoll() {
    clearTimeout(pollTimer);
    if (!mode) return;
    pollTimer = setTimeout(async () => { await refresh(); schedulePoll(); }, mode === "request" ? 1000 : 3000);
  }

  let lastCount = 0;
  function tick() {
    if (mode !== "request") return;
    const count = visibleItems(Date.now()).length;
    render();
    if (count < lastCount) {
      // A request just expired here; let the host drop it without waiting.
      api("/local/remote/popup", { method: "POST", body: JSON.stringify({ action: "refresh" }) }).catch(() => {});
    }
    lastCount = count;
  }

  window.htPopup = Object.freeze({
    show(next) {
      mode = next === "session" ? "session" : "request";
      armedAt = Math.max(armedAt, performance.now() + ARM_DELAY);
      render();
      setTimeout(updateButtons, ARM_DELAY + 20);
      clearInterval(tickTimer);
      tickTimer = setInterval(tick, 1000);
      void refresh().then(schedulePoll);
    },
    hide() {
      mode = ""; shownKey = "";
      clearTimeout(pollTimer); clearInterval(tickTimer);
      $("request").hidden = true; $("session").hidden = true;
    },
  });

  function applyTheme() {
    let preference = "system";
    try { preference = localStorage.getItem("ht_theme") || "system"; } catch (e) {}
    const theme = preference === "dark" || preference === "light" ? preference : matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
  }
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", applyTheme);
  // The main window stores theme and language on the same origin.
  window.addEventListener("storage", (event) => {
    if (event.key === "ht_theme") applyTheme();
    if (event.key === "ht_locale") { locale = event.newValue === "en" ? "en" : "zh-CN"; render(); }
  });
  applyStaticText();
})();
