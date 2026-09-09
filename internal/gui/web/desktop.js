    const strings = {
      "zh-CN": {
        copyAddress: "复制访问地址",
        agentOnline: "本机连接正常",
        agentOffline: "本机尚未连接，请检查网络",
        agentStarting: "正在连接服务器",
        welcomeTitle: "把这台电脑，连接到家。",
        welcomeDetail: "让你的本地服务随时可达。登录自己的服务器，接下来的连接由 Home Tunnel 照顾。",
        stepSignIn: "登录并登记本机",
        stepService: "选择想要发布的本地服务",
        stepShare: "复制地址，随时访问",
        connectComputer: "连接这台电脑",
        thisComputer: "当前设备",
        scopeNote: "这里只显示此设备上的服务。要管理其他设备，请打开控制台或使用手机端。",
        settings: "设置",
        myServices: "本机服务",
        allServices: "全部服务",
        online: "在线",
        paused: "已暂停",
        searchServices: "查找服务",
        statusFilter: "状态",
        all: "全部状态",
        identity: "01 · 服务与访问地址",
        destination: "02 · 本地目标",
        hostHelp: "填写这台电脑能够访问的服务地址。服务运行在本机时使用 127.0.0.1。",
        publishService: "发布本机服务",
        backServices: "返回本机服务",
        sessionTitle: "登录与运行",
        sessionHelp: "关闭窗口后服务仍在后台运行。退出程序会停止本机隧道，退出登录还会清除本机凭据。",
        noMatch: "没有匹配的服务，请调整搜索条件。",
        more: "更多",
        unnamedComputer: "这台电脑",
        loginLead: "这是 Windows、macOS 和 Linux 共用的窗口客户端。关闭窗口会缩到托盘，隧道继续跑；要结束请用托盘或下面的「退出程序」。",
        server: "服务器地址", username: "用户名", password: "密码", newPassword: "请设置新密码（至少 12 个字符）", confirmPassword: "确认新密码", showPassword: "显示", hidePassword: "隐藏", working: "处理中…", failed: "操作失败，请重试", stale: "连接中断，显示缓存。请检查网络并重试。", synced: "最近同步", retryLatest: "读取最新版本并保留输入", conflict: "这条连接已在其他地方修改。请读取最新版本后核对并重新保存。",
        login: "登录并注册本机", quitApp: "退出程序", sync: "立即同步", add: "新建连接",
        console: "打开控制台", logout: "退出账号", name: "名称", subdomain: "公网子域",
        scheme: "本地协议", host: "本地主机", port: "本地端口", enabled: "启用这条连接",
        save: "保存", cancel: "取消", createTitle: "新建 HTTP 连接", editTitle: "编辑 ",
        empty: "还没有连接。点「新建连接」发布家里的 HTTP 服务。", pause: "暂停", enable: "启用",
        remove: "删除", edit: "编辑", copied: "已复制公网地址", connecting: "正在连接…",
        confirmDelete: "确定删除这条连接？公网地址会立即失效。",
        confirmLogout: "退出账号会停止本机隧道，并清除这台电脑上的设备登录状态。",
        confirmQuit: "退出程序会停止本机隧道，但保留已保存的登录状态。下次打开窗口会自动重连。",
        updatePrefix: "有新版本 ", updateCurrent: "（当前 ", updateSuffix: "）。",
        download: "下载到「下载」文件夹并校验", openRelease: "打开 Release", downloading: "正在下载…"
      },
      en: {
        copyAddress: "Copy public address",
        agentOnline: "This computer is connected",
        agentOffline: "This computer is offline. Check the network.",
        agentStarting: "Connecting to the server",
        welcomeTitle: "Connect this computer to home.",
        welcomeDetail: "Keep local services within reach. Sign in to your server and let Home Tunnel handle the connection.",
        stepSignIn: "Sign in and register this computer",
        stepService: "Choose a local service",
        stepShare: "Copy its address and connect anywhere",
        connectComputer: "Connect this computer",
        thisComputer: "THIS COMPUTER",
        scopeNote: "Only services on this device appear here. Manage other devices in the console or Android app.",
        settings: "Settings",
        myServices: "Local services",
        allServices: "All services",
        online: "Online",
        paused: "Paused",
        searchServices: "Find a service",
        statusFilter: "Status",
        all: "All states",
        identity: "01 · Service and public address",
        destination: "02 · Local destination",
        hostHelp: "Enter an address reachable from this computer. Use 127.0.0.1 for a service running here.",
        publishService: "PUBLISH A LOCAL SERVICE",
        backServices: "Back to services",
        sessionTitle: "Session and runtime",
        sessionHelp: "Closing the window keeps services running. Quitting stops local tunnels; signing out also removes this device’s credentials.",
        noMatch: "No matching services. Try another search.",
        more: "More",
        unnamedComputer: "This computer",
        loginLead: "This is the same windowed client for Windows, macOS, and Linux. Closing the window hides it to the tray; tunnels keep running. Use the tray or Quit to stop.",
        server: "Server URL", username: "Username", password: "Password", newPassword: "New password (at least 12 characters)", confirmPassword: "Confirm password", showPassword: "Show", hidePassword: "Hide", working: "Working…", failed: "Operation failed. Retry.", stale: "Connection interrupted. Showing cached data. Check your network and retry.", synced: "Last synced", retryLatest: "Load latest version and keep inputs", conflict: "This connection was edited elsewhere. Load the latest version and review before saving.",
        login: "Sign in and register this PC", quitApp: "Quit", sync: "Sync now", add: "New connection",
        console: "Open console", logout: "Sign out", name: "Name", subdomain: "Public subdomain",
        scheme: "Local scheme", host: "Local host", port: "Local port", enabled: "Enable this connection",
        save: "Save", cancel: "Cancel", createTitle: "New HTTP connection", editTitle: "Edit ",
        empty: "No connections yet. Use New connection to publish a local HTTP service.", pause: "Pause", enable: "Enable",
        remove: "Delete", edit: "Edit", copied: "Public address copied", connecting: "Connecting…",
        confirmDelete: "Delete this connection? The public address will stop working immediately.",
        confirmLogout: "Signing out stops local tunnels and clears this computer's device login.",
        confirmQuit: "Quit stops local tunnels but keeps the saved login. The next window launch will reconnect.",
        updatePrefix: "Version ", updateCurrent: " is available (current ", updateSuffix: ").",
        download: "Download to Downloads and verify SHA-256", openRelease: "Open Release", downloading: "Downloading…"
      }
    };
    const $ = (id) => document.getElementById(id);
    let locale = document.documentElement.lang === "en" ? "en" : "zh-CN";
    const t = (key) => (strings[locale] && strings[locale][key]) || strings["zh-CN"][key] || key;
    function applyLocale() {
      document.documentElement.lang = locale;
      document.querySelectorAll("[data-i18n]").forEach((node) => { node.textContent = t(node.dataset.i18n); });
      $("locale-toggle").textContent = locale === "en" ? "中" : "EN";
      try { localStorage.setItem("ht_locale", locale); } catch (e) {}
    }
    function applyTheme(theme) {
      document.documentElement.dataset.theme = theme;
      document.documentElement.style.colorScheme = theme;
      $("theme-toggle").textContent = theme === "dark" ? "☀" : "◐";
      try { localStorage.setItem("ht_theme", theme); } catch (e) {}
    }
    applyLocale();
    applyTheme(document.documentElement.dataset.theme || "light");
    $("locale-toggle").onclick = () => { locale = locale === "en" ? "zh-CN" : "en"; applyLocale(); renderServices(); };
    $("theme-toggle").onclick = () => applyTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark");
    $("server").value = localStorage.getItem("ht_server") || "";
    $("username").value = localStorage.getItem("ht_username") || "";
    const localSessionToken = new URLSearchParams(location.hash.slice(1)).get("session") || "";
    async function api(path, options = {}) {
      const response = await fetch(path, { ...options, headers: { "content-type": "application/json", ...(options.headers || {}), ...(localSessionToken ? { authorization: `Bearer ${localSessionToken}` } : {}) } });
      const text = await response.text();
      const data = text ? JSON.parse(text) : null;
      if (!response.ok) { const error = new Error(data?.message || text || response.statusText); error.code = data?.error_code; throw error; }
      return data;
    }
    function escapeHtml(value) {
      return String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
    }
    let consoleUrl = "";
    let connections = [];
    let editBaseline = null;
    let editVersion = null;
    let lastUpdateCheck = 0;
    let refreshing = false;
    async function runAction(button, action, errorId = "status") {
      if (button.disabled) return;
      const label = button.textContent; button.disabled = true; button.textContent = t("working");
      try { await action(); } catch (error) { $(errorId).textContent = error.message || t("failed"); }
      finally { if (button.isConnected) { button.disabled = false; button.textContent = label; } }
    }
    $("show-password").onclick = () => { const showing = $("password").type === "password"; $("password").type = showing ? "text" : "password"; $("show-password").textContent = t(showing ? "hidePassword" : "showPassword"); };

    function resetEditor() {
      editBaseline = null; editVersion = null;
      $("edit-id").value = "";
      $("editor-title").textContent = t("createTitle");
      $("name").value = "";
      $("subdomain").value = "";
      $("scheme").value = "http"; $("scheme").disabled = false; $("scheme").classList.remove("hidden"); document.querySelector('label[for="scheme"]').classList.remove("hidden");
      $("host").value = "127.0.0.1";
      $("port").value = "8080";
      $("enabled").checked = true;
      $("availability").textContent = "";
      $("suggestions").replaceChildren();
      $("edit-error").textContent = "";
    }
    function fillEditor(item) {
      editBaseline = { ...item }; editVersion = item.version;
      $("edit-id").value = item.id;
      $("editor-title").textContent = t("editTitle") + (item.name || "");
      $("name").value = item.name || "";
      $("subdomain").value = item.subdomain || "";
      $("scheme").value = item.local_scheme || "http";
      $("host").value = item.local_host || "127.0.0.1";
      $("port").value = String(item.local_port || 8080);
      $("enabled").checked = item.enabled !== false;
      const raw = ["tcp", "udp"].includes(item.proxy_type);
      $("scheme").disabled = raw; $("scheme").closest("form").querySelector('label[for="scheme"]').classList.toggle("hidden", raw);
      $("scheme").classList.toggle("hidden", raw);
      $("edit-error").textContent = "";
      $("subdomain").dispatchEvent(new Event("input"));
    }
    async function quitApp() {
      if (!confirm(t("confirmQuit"))) return;
      await api("/local/quit", { method: "POST" });
      document.body.innerHTML = "<main><p class='muted'>" + escapeHtml(t("quitApp")) + "</p></main>";
    }
    async function showHome(background = false) {
      if (refreshing || background && (!$("editor").classList.contains("hidden") || !$("login").classList.contains("hidden") || !$("settings").classList.contains("hidden"))) return;
      refreshing = true;
      try {
      $("settings").classList.add("hidden");
      $("login").classList.add("hidden");
      $("editor").classList.add("hidden");
      $("home").classList.remove("hidden");
      const state = await api("/local/state");
      consoleUrl = state.console_url || "";
      if (!state.enrolled) { $("home").classList.add("hidden"); $("login").classList.remove("hidden"); return; }
      $("machine-name").textContent = state.device_name || t("unnamedComputer");
      $("machine-version").textContent = "Home Tunnel " + (state.version || "6.0.0");
      $("settings-server").textContent = consoleUrl;
      $("count-total").textContent = (state.connections || []).length;
      $("count-online").textContent = (state.connections || []).filter(c => c.enabled && c.state === "Online").length;
      $("count-paused").textContent = (state.connections || []).filter(c => !c.enabled).length;
      $("status").textContent = state.stale ? t("stale") : `${t(state.agent_state === "Online" ? "agentOnline" : state.agent_state === "Starting" ? "agentStarting" : "agentOffline")} · ${t("synced")} ${new Date(state.last_synced_at || Date.now()).toLocaleTimeString(locale)}`;
      if (Date.now() - lastUpdateCheck > 3600000) {
      lastUpdateCheck = Date.now();
      $("update").replaceChildren();
      void (async () => { try {
        const update = await api("/local/update");
        if (update.newer) {
          $("update").append(t("updatePrefix") + update.latest + t("updateCurrent") + update.current + t("updateSuffix") + " ");
          if (update.download_url) {
            const download = document.createElement("button");
            download.className = "chip";
            download.textContent = t("download");
            download.onclick = async () => {
              download.disabled = true;
              download.textContent = t("downloading");
              try {
                const result = await api("/local/update/download", { method: "POST" });
                $("update").textContent = result.hint || result.path;
              } catch (error) {
                $("update").textContent = error.message;
              }
            };
            $("update").append(download);
          }
          if (update.url) {
            const link = document.createElement("a");
            link.href = update.url;
            link.target = "_blank";
            link.rel = "noreferrer";
            link.textContent = " " + t("openRelease");
            $("update").append(link);
          }
        }
      } catch { /* optional update metadata */ } })();
      }
      connections = state.connections || [];
      renderServices();
      } finally { refreshing = false; }
    }
    function renderServices() {
      const search = $("service-search").value.trim().toLowerCase();
      const filter = $("service-filter").value;
      const items = connections.filter(item => (!search || `${item.name} ${item.subdomain} ${item.local_host}`.toLowerCase().includes(search)) && (filter === "all" || filter === "paused" && !item.enabled || filter === "online" && item.enabled && item.state === "Online"));
      $("connections").innerHTML = items.length ? items.map(item => {
        const publicUrl = item.public_url || item.public_endpoint || "";
        const status = !item.enabled ? t("paused") : item.state === "Online" ? t("online") : item.state || "—";
        return `<article class="service-row"><div class="service-identity"><span class="service-protocol">${escapeHtml((item.proxy_type || "http").toUpperCase())}</span><div><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.local_host)}:${escapeHtml(item.local_port)}</small></div></div><span class="state-badge ${item.enabled && item.state === "Online" ? "online" : ""}">${escapeHtml(status)}</span><button type="button" class="url" data-copy="${escapeHtml(publicUrl)}" aria-label="${escapeHtml(t("copyAddress"))}">${escapeHtml(publicUrl || item.subdomain)}</button><div class="actions"><button class="secondary" data-edit="${escapeHtml(item.id)}">${escapeHtml(t("edit"))}</button><button class="secondary" data-toggle="${escapeHtml(item.id)}" data-enabled="${item.enabled}">${escapeHtml(t(item.enabled ? "pause" : "enable"))}</button><details><summary>${escapeHtml(t("more"))}</summary><button class="danger" data-delete="${escapeHtml(item.id)}">${escapeHtml(t("remove"))}</button></details></div></article>`;
      }).join("") : `<div class="empty-state"><strong>${escapeHtml(t(items.length || connections.length ? "noMatch" : "empty"))}</strong>${!connections.length ? `<button id="empty-add">${escapeHtml(t("add"))}</button>` : ""}</div>`;
      $("empty-add")?.addEventListener("click", () => $("add").click());
      document.querySelectorAll("[data-copy]").forEach((node) => node.addEventListener("click", async () => {
        if (!node.dataset.copy) return;
        await runAction(node, async () => { await navigator.clipboard.writeText(node.dataset.copy); $("status").textContent = t("copied"); });
      }));
      document.querySelectorAll("[data-edit]").forEach((node) => node.addEventListener("click", () => {
        const item = connections.find((value) => value.id === node.dataset.edit);
        if (!item) return;
        fillEditor(item);
        $("home").classList.add("hidden");
        $("editor").classList.remove("hidden");
      }));
      document.querySelectorAll("[data-delete]").forEach((node) => node.addEventListener("click", async () => {
        if (!confirm(t("confirmDelete"))) return;
        await runAction(node, async () => { await api("/local/connections/" + node.dataset.delete, { method: "DELETE" }); await showHome(); });
      }));
      document.querySelectorAll("[data-toggle]").forEach((node) => node.addEventListener("click", async () => {
        await runAction(node, async () => { await api("/local/connections/" + node.dataset.toggle, { method: "PATCH", body: JSON.stringify({ enabled: node.dataset.enabled !== "true" }) }); await showHome(); });
      }));
    }
    $("service-search").oninput = renderServices;
    $("service-filter").onchange = renderServices;
    $("settings-open").onclick = () => { $("home").classList.add("hidden"); $("settings").classList.remove("hidden"); };
    $("settings-back").onclick = () => runAction($("settings-back"), () => showHome(), "settings-error");
    $("login-form").onsubmit = async (event) => {
      event.preventDefault();
      if (!$("login-form").reportValidity()) return;
      if (!$("password-change").classList.contains("hidden") && $("new-password").value !== $("confirm-password").value) { $("login-error").textContent = locale === "en" ? "Passwords do not match" : "两次新密码不一致"; return; }
      await runAction($("login-button"), async () => {
      $("login-error").textContent = "";
      try {
        localStorage.setItem("ht_server", $("server").value);
        localStorage.setItem("ht_username", $("username").value);
        await api("/local/login", { method: "POST", body: JSON.stringify({ server: $("server").value, username: $("username").value, password: $("password").value, new_password: $("new-password").value }) });
        $("password").value = ""; $("new-password").value = ""; $("confirm-password").value = "";
        await showHome();
      } catch (error) {
        if (/requires a password change|PASSWORD_CHANGE_REQUIRED/.test(error.message)) {
          $("password-change").classList.remove("hidden"); $("new-password").required = true; $("confirm-password").required = true; $("new-password").focus();
          $("login-error").textContent = locale === "en" ? "Set a new password to continue." : "首次登录请设置新密码后继续。";
        } else $("login-error").textContent = error.message;
      }
      }, "login-error");
    };
    $("refresh").onclick = () => runAction($("refresh"), () => showHome());
    $("console").onclick = () => { if (consoleUrl) window.open(consoleUrl, "_blank", "noopener,noreferrer"); };
    $("logout").onclick = async () => {
      if (!confirm(t("confirmLogout"))) return;
      await runAction($("logout"), async () => {
        await api("/local/logout", { method: "POST" });
        location.reload();
      }, "settings-error");
    };
    $("quit-login").onclick = () => runAction($("quit-login"), quitApp, "login-error");
    $("quit-home").onclick = () => runAction($("quit-home"), quitApp, "settings-error");
    $("add").onclick = () => { resetEditor(); $("home").classList.add("hidden"); $("editor").classList.remove("hidden"); };
    $("cancel").onclick = () => runAction($("cancel"), () => showHome());
    let availabilityRequest = 0, availabilityTimer;
    $("subdomain").addEventListener("input", () => {
      const requestId = ++availabilityRequest;
      clearTimeout(availabilityTimer);
      availabilityTimer = setTimeout(async () => {
      const name = $("subdomain").value.trim();
      if (!name) return;
      try {
        if (editBaseline && name === editBaseline.subdomain) { $("availability").textContent = locale === "en" ? "Your current address" : "当前连接使用的地址"; return; }
        const result = await api("/local/subdomain?name=" + encodeURIComponent(name));
        if (requestId !== availabilityRequest || $("subdomain").value.trim() !== name) return;
        $("availability").textContent = result.message || "";
        $("suggestions").replaceChildren(...(result.suggestions || []).map((item) => {
          const button = document.createElement("button");
          button.type = "button";
          button.className = "secondary chip";
          button.textContent = item;
          button.onclick = () => { $("subdomain").value = item; $("subdomain").dispatchEvent(new Event("input")); };
          return button;
        }));
      } catch { /* advisory only */ }
      }, 250);
    });
    $("editor-form").onsubmit = async (event) => {
      event.preventDefault();
      if (!$("editor-form").reportValidity()) return;
      await runAction($("save"), async () => {
      $("edit-error").textContent = "";
      const payload = { name: $("name").value, subdomain: $("subdomain").value, local_host: $("host").value, local_port: Number($("port").value), local_scheme: $("scheme").value, enabled: $("enabled").checked };
      try {
        const id = $("edit-id").value;
        if (id) {
          const patch = Object.fromEntries(Object.entries(payload).filter(([key, value]) => value !== editBaseline?.[key]));
          if ($("scheme").disabled) delete patch.local_scheme;
          await api("/local/connections/" + id, { method: "PATCH", body: JSON.stringify({ ...patch, expected_version: editVersion }) });
        }
        else await api("/local/connections", { method: "POST", body: JSON.stringify(payload) });
        await showHome();
      } catch (error) {
        $("edit-error").textContent = error.message;
        if (/VERSION_CONFLICT/.test(error.message)) {
          $("edit-error").textContent = t("conflict");
          const latest = document.createElement("button"); latest.type = "button"; latest.className = "secondary"; latest.textContent = t("retryLatest");
          latest.onclick = () => runAction(latest, async () => {
            const data = await api("/local/connections"); const item = data.items.find((c) => c.id === $("edit-id").value);
            if (!item) throw new Error(t("failed")); editVersion = item.version;
            $("edit-error").textContent = locale === "en" ? "Latest version loaded. Review your changes and save again." : "已读取最新版本。输入保持不变，请核对并重新保存。";
          }, "edit-error");
          $("edit-error").append(latest);
        }
      }
      }, "edit-error");
    };
    api("/local/state").then((state) => { if (state.enrolled) return showHome(); }).catch(() => { $("login-error").textContent = t("failed"); });

    setInterval(() => { if (!document.hidden) showHome(true).catch(() => { $("status").textContent = t("stale"); }); }, 30000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) showHome(true).catch(() => { $("status").textContent = t("stale"); }); });
