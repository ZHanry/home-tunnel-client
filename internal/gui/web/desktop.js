    const strings = {
      "zh-CN": { select: "选择", batchPause: "暂停所选", batchResume: "恢复所选", tags: "设备标签（逗号分隔，最多 12 个）", favorite: "收藏此设备", metadata: "设备标记", saveMetadata: "保存标记", loginMethod: "接入方式", accountLogin: "账号密码", codeLogin: "一次性接入码", enrollmentCode: "接入码（在控制台的我的账号页面生成）", mfaCode: "动态码或恢复码（已启用双重验证时填写）",
        connectionType: "连接类型",
        typeWeb: "Web · HTTP / HTTPS",
        typeRtsp: "RTSP 摄像头 · TCP",
        typeSsh: "SSH · TCP",
        typeRdp: "远程桌面 RDP · TCP",
        typeTcp: "通用 TCP",
        typeUdp: "通用 UDP",
        rawPortNote: "公网端口由服务端自动分配，限于管理员已开放的范围。TCP/UDP 的认证与加密由目标应用提供。",
        rtspNote: "播放器必须使用 RTSP over TCP（交错传输）。复制地址后补上摄像头的流路径，例如 /Streaming/Channels/101。",
        udpNote: "适用于固定端口 UDP 服务。动态媒体端口协商需要额外配置。",
        serverUpgrade: "此服务端尚未提供客户端 TCP/UDP 创建能力，请升级服务端至 7.0.0。",
        transportDisabled: "服务端未开放此传输类型。请管理员启用对应的 TCP/UDP 端口范围和防火墙。",
        rawNotAllowed: "管理员尚未允许普通用户自行创建 TCP/UDP 连接。请在控制台的系统设置中授权。",
        rawUnavailableOffline: "无法确认服务器的端口能力，请恢复连接后重试。",
        assignedAddress: "已分配的公网地址：",
        rtspDefaultName: "摄像头",
        sshDefaultName: "SSH 终端",
        rdpDefaultName: "远程桌面",

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
        save: "保存", cancel: "取消", createTitle: "新建连接", editTitle: "编辑 ",
        empty: "还没有连接。点「新建连接」发布这台设备上的服务。", pause: "暂停", enable: "启用",
        remove: "删除", edit: "编辑", copied: "已复制公网地址", connecting: "正在连接…",
        confirmDelete: "确定删除这条连接？公网地址会立即失效。",
        confirmLogout: "退出账号会停止本机隧道，并清除这台电脑上的设备登录状态。",
        confirmQuit: "退出程序会停止本机隧道，但保留已保存的登录状态。下次打开窗口会自动重连。",
        updatePrefix: "有新版本 ", updateCurrent: "（当前 ", updateSuffix: "）。",
        download: "下载到「下载」文件夹并校验", openRelease: "打开 Release", downloading: "正在下载…"
      },
      en: { select: "Select", batchPause: "Pause selected", batchResume: "Resume selected", tags: "Device tags (comma separated, up to 12)", favorite: "Favorite this device", metadata: "Device organization", saveMetadata: "Save tags", loginMethod: "Sign-in method", accountLogin: "Account and password", codeLogin: "One-time enrollment code", enrollmentCode: "Enrollment code (create in your console account page)", mfaCode: "Authenticator or recovery code (if MFA is enabled)",
        connectionType: "Connection type",
        typeWeb: "Web · HTTP / HTTPS",
        typeRtsp: "RTSP camera · TCP",
        typeSsh: "SSH · TCP",
        typeRdp: "Remote desktop RDP · TCP",
        typeTcp: "General TCP",
        typeUdp: "General UDP",
        rawPortNote: "The server assigns a public port from the administrator’s configured range. The target application provides authentication and encryption.",
        rtspNote: "Use RTSP over TCP (interleaved mode) in your player. Append the camera stream path, such as /Streaming/Channels/101, to the copied address.",
        udpNote: "For fixed-port UDP services. Dynamic media-port negotiation needs additional configuration.",
        serverUpgrade: "Upgrade the server to 7.0.0 to create TCP/UDP connections here.",
        transportDisabled: "The server has not enabled this transport. Ask the administrator to configure the matching TCP/UDP port range and firewall.",
        rawNotAllowed: "The administrator has not enabled TCP/UDP self-service for regular users. Permission is managed in console settings.",
        rawUnavailableOffline: "Reconnect to the server to check port availability.",
        assignedAddress: "Assigned public address: ",
        rtspDefaultName: "Camera",
        sshDefaultName: "SSH terminal",
        rdpDefaultName: "Remote desktop",

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
        save: "Save", cancel: "Cancel", createTitle: "New connection", editTitle: "Edit ",
        empty: "No connections yet. Use New connection to publish a service from this device.", pause: "Pause", enable: "Enable",
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
    $("locale-toggle").onclick = () => { locale = locale === "en" ? "zh-CN" : "en"; applyLocale(); renderServices(); if (!$("editor").classList.contains("hidden")) applyProtocol(); };
    $("theme-toggle").onclick = () => applyTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark");
    $("server").value = localStorage.getItem("ht_server") || "";
    $("username").value = localStorage.getItem("ht_username") || "";
    const localSessionToken = new URLSearchParams(location.hash.slice(1)).get("session") || "";
    async function api(path, options = {}) {
      const response = await fetch(path, { ...options, headers: { "content-type": "application/json", ...(options.headers || {}), ...(localSessionToken ? { authorization: `Bearer ${localSessionToken}` } : {}) } });
      const text = await response.text();
      const data = text ? JSON.parse(text) : null;
      if (!response.ok) {
        const descriptions = { CLIENT_RAW_TUNNELS_DISABLED: t("rawNotAllowed"), TCP_TUNNELS_DISABLED: t("transportDisabled"), UDP_TUNNELS_DISABLED: t("transportDisabled"), PORT_POOL_EXHAUSTED: locale === "en" ? "The server has no available public ports. Ask the administrator to expand the range." : "服务端公网端口已用完，请联系管理员扩容。", VERSION_CONFLICT: t("conflict") };
        const error = new Error(descriptions[data?.error_code] || data?.message || text || response.statusText); error.code = data?.error_code; throw error;
      }
      return data;
    }
    function escapeHtml(value) {
      return String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
    }
    let consoleUrl = "";
    let connections = [];
    let capabilities = {};
    let serverStale = false;
    const protocols = {
      http: { transport: "http", port: 8080 }, tcp: { transport: "tcp", port: 8080 },
      udp: { transport: "udp", port: 51820 }, rtsp: { transport: "tcp", port: 554, app: "rtsp" },
      ssh: { transport: "tcp", port: 22, app: "ssh" }, rdp: { transport: "tcp", port: 3389, app: "rdp" }
    };
    function creationBlock(preset) {
      if (preset.transport === "http" || $("edit-id").value) return "";
      if (serverStale) return t("rawUnavailableOffline");
      if (!capabilities.supported) return t("serverUpgrade");
      const transport = capabilities[preset.transport] || {};
      if (!transport.enabled) return t("transportDisabled");
      return transport.can_create ? "" : t("rawNotAllowed");
    }
    function applyProtocol(useDefaults = false) {
      const kind = $("protocol").value;
      const preset = protocols[kind] || protocols.http;
      const raw = preset.transport !== "http";
      $("web-address").classList.toggle("hidden", raw);
      $("web-scheme").classList.toggle("hidden", raw);
      $("subdomain").required = !raw;
      $("subdomain").disabled = raw;
      $("scheme").disabled = raw;
      if (useDefaults && !$("edit-id").value) {
        $("port").value = preset.port;
        if (!$("name").value && preset.app) $("name").value = t(preset.app + "DefaultName");
      }
      const blocked = creationBlock(preset);
      const details = [blocked || (raw ? t("rawPortNote") : "")];
      if (kind === "rtsp") details.push(t("rtspNote"));
      if (kind === "udp") details.push(t("udpNote"));
      if (raw && editBaseline?.public_endpoint) details.push(t("assignedAddress") + (editBaseline.access_url || editBaseline.public_endpoint));
      $("transport-note").textContent = details.filter(Boolean).join("\n");
      $("transport-note").classList.toggle("unavailable", Boolean(blocked));
      $("save").disabled = Boolean(blocked);
    }
    $("protocol").onchange = () => applyProtocol(true);
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
      $("protocol").value = "http"; $("protocol").disabled = false;
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
      applyProtocol();
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
      $("protocol").value = item.application_protocol || item.proxy_type || "http";
      $("protocol").disabled = true;
      applyProtocol();
      $("edit-error").textContent = "";
      $("subdomain").dispatchEvent(new Event("input"));
    }
    async function quitApp() {
      if (!confirm(t("confirmQuit"))) return;
	  resetRemoteHostUI();
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
      capabilities = state.capabilities || {}; serverStale = Boolean(state.stale);
      if (!state.enrolled) { $("home").classList.add("hidden"); $("login").classList.remove("hidden"); return; }
	  void refreshRemoteHost();
      $("machine-name").textContent = state.device_name || t("unnamedComputer");
      $("machine-version").textContent = "Home Tunnel " + (state.version || "8.0.0-rc.1");
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
                if (result.verified !== true) throw new Error("更新包未通过 SHA-256 校验 / Update verification failed");
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
      } catch (error) { $("update").textContent = error.message; } })();
      }
      connections = state.connections || [];
      renderServices();
      } finally { refreshing = false; }
    }
    const selectedConnections = new Set();
    let deviceMetadata = null;
    function renderServices() {
      for (const id of selectedConnections) if (!connections.some(item => item.id === id)) selectedConnections.delete(id);
      $("batch-pause").disabled = $("batch-resume").disabled = selectedConnections.size === 0;
      $("batch-count").textContent = `${selectedConnections.size} / 50`;
      const search = $("service-search").value.trim().toLowerCase();
      const filter = $("service-filter").value;
      const items = connections.filter(item => (!search || `${item.name} ${item.subdomain} ${item.local_host}`.toLowerCase().includes(search)) && (filter === "all" || filter === "paused" && !item.enabled || filter === "online" && item.enabled && item.state === "Online"));
      $("connections").innerHTML = items.length ? items.map(item => {
        const publicUrl = item.public_url || item.access_url || item.public_endpoint || "";
        const status = !item.enabled ? t("paused") : item.state === "Online" ? t("online") : item.state || "—";
        return `<article class="service-row"><div class="service-identity"><input type="checkbox" class="batch-select" style="width:18px;min-height:18px" data-select="${escapeHtml(item.id)}" aria-label="${escapeHtml(t("select") + ": " + item.name)}" ${selectedConnections.has(item.id) ? "checked" : ""}><span class="service-protocol">${escapeHtml((item.application_protocol || item.proxy_type || "http").toUpperCase())}</span><div><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.local_host)}:${escapeHtml(item.local_port)}</small></div></div><span class="state-badge ${item.enabled && item.state === "Online" ? "online" : ""}">${escapeHtml(status)}</span><button type="button" class="url" data-copy="${escapeHtml(publicUrl)}" aria-label="${escapeHtml(t("copyAddress"))}">${escapeHtml(publicUrl || item.subdomain)}</button><div class="actions"><button class="secondary" data-edit="${escapeHtml(item.id)}">${escapeHtml(t("edit"))}</button><button class="secondary" data-toggle="${escapeHtml(item.id)}" data-enabled="${item.enabled}">${escapeHtml(t(item.enabled ? "pause" : "enable"))}</button><details><summary>${escapeHtml(t("more"))}</summary><button class="danger" data-delete="${escapeHtml(item.id)}">${escapeHtml(t("remove"))}</button></details></div></article>`;
      }).join("") : `<div class="empty-state"><strong>${escapeHtml(t(items.length || connections.length ? "noMatch" : "empty"))}</strong>${!connections.length ? `<button id="empty-add">${escapeHtml(t("add"))}</button>` : ""}</div>`;
      document.querySelectorAll("[data-select]").forEach(node => node.addEventListener("change", () => {
        if (node.checked && selectedConnections.size < 50) selectedConnections.add(node.dataset.select);
        else { selectedConnections.delete(node.dataset.select); node.checked = false; }
        $("batch-pause").disabled = $("batch-resume").disabled = selectedConnections.size === 0;
        $("batch-count").textContent = `${selectedConnections.size} / 50`;
      }));
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
    $("settings-open").onclick = () => runAction($("settings-open"), async () => {
      $("home").classList.add("hidden"); $("settings").classList.remove("hidden");
	  void refreshRemoteHost();
      $("metadata-save").disabled = true; deviceMetadata = null;
      deviceMetadata = await api("/local/device/metadata");
      $("device-tags").value = (deviceMetadata.tags || []).join(", ");
      $("device-favorite").checked = !!deviceMetadata.favorite;
      $("metadata-save").disabled = !deviceMetadata.metadata_version;
    }, "settings-error");
    $("metadata-save").onclick = () => runAction($("metadata-save"), async () => {
      if (!deviceMetadata) return;
      const tags = [...new Set($("device-tags").value.split(",").map(tag => tag.trim()).filter(Boolean))];
      await api("/local/device/metadata", { method: "PATCH", body: JSON.stringify({tags, favorite: $("device-favorite").checked, expected_metadata_version: deviceMetadata.metadata_version}) });
      deviceMetadata = await api("/local/device/metadata");
      $("settings-error").textContent = locale === "en" ? "Saved" : "已保存";
    }, "settings-error");
    for (const enabled of [false, true]) {
      const button = $(enabled ? "batch-resume" : "batch-pause");
      button.onclick = () => runAction(button, async () => {
        const items = connections.filter(item => selectedConnections.has(item.id));
        if (!items.length || items.length > 50) return;
        const verb = t(enabled ? "batchResume" : "batchPause");
        if (!confirm(`${verb} (${items.length})?\n${items.map(item => item.name).join("\n")}`)) return;
        const result = await api("/local/batch", {method: "POST", body: JSON.stringify({enabled, items: items.map(item => ({id:item.id,expected_version:item.version}))})});
        $("batch-results").textContent = result.results.map(row => `${items.find(item => item.id === row.id)?.name || row.id}: ${row.status === 200 ? (locale === "en" ? "Saved" : "已保存") : row.error_code || row.status}`).join("\n");
        selectedConnections.clear(); await showHome();
      });
    }
    $("settings-back").onclick = () => runAction($("settings-back"), () => showHome(), "settings-error");
    $("login-method").onchange = () => {
      const code = $("login-method").value === "code";
      $("account-fields").classList.toggle("hidden", code);
      $("code-fields").classList.toggle("hidden", !code);
      $("username").required = $("password").required = !code;
      $("enrollment-code").required = code;
      $("new-password").required = $("confirm-password").required = false;
      $("new-password").value = $("confirm-password").value = "";
      $("password").value = $("mfa-code").value = $("enrollment-code").value = "";
      $("new-password").value = $("confirm-password").value = "";
      $("password-change").classList.add("hidden");
    };
    $("login-form").onsubmit = async (event) => {
      event.preventDefault();
      if (!$("login-form").reportValidity()) return;
      if (!$("password-change").classList.contains("hidden") && $("new-password").value !== $("confirm-password").value) { $("login-error").textContent = locale === "en" ? "Passwords do not match" : "两次新密码不一致"; return; }
      await runAction($("login-button"), async () => {
	  resetRemoteHostUI();
      $("login-error").textContent = "";
      try {
        localStorage.setItem("ht_server", $("server").value);
        localStorage.setItem("ht_username", $("username").value);
        await api("/local/login", { method: "POST", body: JSON.stringify({ server: $("server").value, username: $("username").value, password: $("password").value, new_password: $("new-password").value, mfa_code: $("mfa-code").value, enrollment_code: $("enrollment-code").value }) });
        $("password").value = $("new-password").value = $("confirm-password").value = $("mfa-code").value = $("enrollment-code").value = "";
        await showHome();
      } catch (error) {
        if (/requires a password change|PASSWORD_CHANGE_REQUIRED/.test(error.message)) {
          $("password-change").classList.remove("hidden"); $("new-password").required = true; $("confirm-password").required = true; $("new-password").focus();
          $("login-error").textContent = locale === "en" ? "Set a new password to continue." : "首次登录请设置新密码后继续。";
        } else $("login-error").textContent = error.message;
      }
      }, "login-error");
    };
    $("doctor-run").onclick = () => runAction($("doctor-run"), async () => {
      const report = await api("/local/doctor");
      $("doctor-result").textContent = report.checks.map(check => `[${check.status}] ${check.name}: ${check.message}`).join("\n");
    }, "settings-error");
    $("support-bundle").onclick = () => runAction($("support-bundle"), async () => {
      const result = await api("/local/doctor", {method:"POST"});
      $("doctor-result").textContent = result.path;
    }, "settings-error");
    $("refresh").onclick = () => runAction($("refresh"), () => showHome());
    $("console").onclick = () => { if (consoleUrl) window.open(consoleUrl, "_blank", "noopener,noreferrer"); };
    $("logout").onclick = async () => {
      if (!confirm(t("confirmLogout"))) return;
	  resetRemoteHostUI();
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
      if ($("protocol").value !== "http") return;
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
      const selected = protocols[$("protocol").value] || protocols.http;
      const blocked = creationBlock(selected);
      if (blocked) { $("edit-error").textContent = blocked; return; }
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
        else {
          payload.proxy_type = selected.transport;
          if (selected.app) payload.application_protocol = selected.app;
          if (selected.transport !== "http") { delete payload.subdomain; payload.local_scheme = "http"; }
          await api("/local/connections", { method: "POST", body: JSON.stringify(payload) });
        }
        await showHome();
      } catch (error) {
        $("edit-error").textContent = error.message;
        if (error.code === "VERSION_CONFLICT" || /VERSION_CONFLICT/.test(error.message)) {
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
    let remoteHostLoading = false, remoteHostTrust = null, remoteHostListSignature = "", remoteHostGeneration = 0;
    let remoteHostAbort = new AbortController();
    function resetRemoteHostUI() {
      remoteHostGeneration++; remoteHostAbort.abort(); remoteHostAbort = new AbortController();
      remoteHostTrust = null; remoteHostListSignature = "";
      $("rd-host-password").value = ""; $("rd-host-mfa").value = ""; $("rd-host-trust").textContent = "";
      $("rd-host-trust-confirm").checked = false; $("rd-host-enroll-submit").disabled = true;
      $("rd-host-pending").replaceChildren(); $("rd-host-grants").replaceChildren();
      for (const id of ["enable", "disable", "stop"]) $("rd-host-" + id).disabled = true;
    }
    const remotePermissionNames = {
      view: "屏幕 / Screen", "input.keyboard": "键盘 / Keyboard", "input.pointer": "鼠标 / Pointer", "input.text": "文字输入 / Text input",
      "audio.system": "系统声音 / System audio", "audio.microphone": "麦克风回传 / Microphone", "clipboard.read": "读取本机剪贴板 / Read local clipboard",
      "clipboard.write": "写入本机剪贴板 / Write local clipboard", "files.send": "发送文件到本机 / Send files here", "files.receive": "从本机接收文件 / Receive files"
    };
    async function remoteHostAction(action, extra = {}) {
      try { return await api("/local/remote/action", { method: "POST", body: JSON.stringify({ action, ...extra }), signal:remoteHostAbort.signal }); }
      finally { void refreshRemoteHost(); }
    }
    function remoteActionButton(label, action, extra, danger = false) {
      const button = document.createElement("button"); button.type = "button"; button.textContent = label; button.className = danger ? "danger" : "secondary";
      button.onclick = () => runAction(button, () => remoteHostAction(action, extra), "rd-host-error");
      return button;
    }
    function renderRemoteApprovals(state) {
      const signature = JSON.stringify([state.pending, state.grants]);
      if (remoteHostListSignature === signature) return;
      remoteHostListSignature = signature;
      $("rd-host-pending").replaceChildren(); $("rd-host-grants").replaceChildren();
      for (const event of state.pending || []) {
        const box = document.createElement("div"), title = document.createElement("h3"), detail = document.createElement("p"), scopes = document.createElement("p"), actions = document.createElement("div");
        box.className = "settings-card"; actions.className = "row";
        title.textContent = event.kind === "session" ? "远程会话请求 / Session request" : "配对请求 / Pairing request";
        detail.textContent = `${event.controller_endpoint_id} · ${event.controller_thumbprint || ""}`; detail.style.overflowWrap = "anywhere";
        scopes.textContent = (event.permissions || []).map(name => remotePermissionNames[name] || name).join(" · ");
        box.append(title, detail, scopes);
        if (event.display_code) {
          const code = document.createElement("p"); code.textContent = `核对码 / Compare code: ${event.display_code}。请在控制端核对一致后确认。`; box.append(code);
        } else {
          const mode = document.createElement("p"); mode.textContent = event.mode === "persistent" ? "持续授权，10 分钟后过期 / Persistent grant, expires in 10 minutes" : "仅本次会话 / This session only"; box.append(mode);
          const data = {id:event.id,kind:event.kind,permissions:event.permissions,mode:event.mode,connection_epoch:event.connection_epoch,state_version:event.state_version};
          actions.append(remoteActionButton("允许以上权限 / Allow listed permissions", "approve", data), remoteActionButton("拒绝 / Reject", "reject", data, true));
          box.append(actions);
        }
        $("rd-host-pending").append(box);
      }
      for (const grant of state.grants || []) {
        if (grant.revoked || Date.parse(grant.expires_at) <= Date.now()) continue;
        const row = document.createElement("div"), detail = document.createElement("p"); row.className = "settings-card";
        detail.textContent = `${grant.controller_endpoint_id} · ${(grant.permissions || []).map(name => remotePermissionNames[name] || name).join(" · ")} · ${new Date(grant.expires_at).toLocaleString(locale)}`;
        detail.style.overflowWrap = "anywhere";
        row.append(detail, remoteActionButton("撤销授权并断开 / Revoke and disconnect", "revoke", {id:grant.id}, true)); $("rd-host-grants").append(row);
      }
    }
    async function refreshRemoteHost() {
      if (remoteHostLoading || !$("rd-host-status") || !$("login").classList.contains("hidden")) return;
      remoteHostLoading = true;
      const generation = remoteHostGeneration;
      try {
        const state = await api("/local/remote/state", {signal:remoteHostAbort.signal});
        if (generation !== remoteHostGeneration || !$("login").classList.contains("hidden")) return;
        const ready = state.capabilities?.available === true;
        $("rd-host-status").textContent = !ready ? "此安装包暂未提供可用的远控后端 / Remote backend unavailable" : state.active_session_id ? "远程会话进行中 / Remote session active" : state.enabled ? "已允许连接，等待本机批准 / Enabled; local approval required" : "远程连接已关闭 / Disabled";
        $("rd-host-detail").textContent = [state.error_code, state.endpoint_id, ...(state.capabilities?.permissions || []).map(name => remotePermissionNames[name] || name)].filter(Boolean).join(" · ");
        $("rd-host-enable").disabled = !ready || !state.enrolled || state.enabled && state.running;
        $("rd-host-disable").disabled = !state.enabled;
        $("rd-host-stop").disabled = !state.active_session_id;
        $("rd-host-enroll").classList.toggle("hidden", !ready || state.enrolled);
        if (state.enrolled || !ready) { $("rd-host-password").value = ""; $("rd-host-mfa").value = ""; }
        renderRemoteApprovals(state);
        const count = (state.pending || []).filter(event => !event.display_code).length;
        $("settings-open").textContent = t("settings") + (count ? ` · ${count} 待批准 / pending` : "");
      } catch {
        if (generation !== remoteHostGeneration) return;
        $("rd-host-status").textContent = "无法读取远控状态 / Remote status unavailable";
        for (const id of ["enable", "disable", "stop"]) $("rd-host-" + id).disabled = id === "enable";
      }
      finally { remoteHostLoading = false; }
    }
    for (const action of ["enable", "disable", "stop"]) $("rd-host-" + action).onclick = () => runAction($("rd-host-" + action), () => remoteHostAction(action), "rd-host-error");
    $("rd-host-trust-load").onclick = () => runAction($("rd-host-trust-load"), async () => {
      remoteHostTrust = null; $("rd-host-trust-confirm").checked = false; $("rd-host-enroll-submit").disabled = true;
      const generation = remoteHostGeneration;
      const trust = await api("/local/remote/trust", {signal:remoteHostAbort.signal});
      if (generation !== remoteHostGeneration || !$("login").classList.contains("hidden")) return;
      remoteHostTrust = trust;
      $("rd-host-trust").textContent = `${trust.origin}\n实例 / Instance: ${trust.server_instance_id}\n密钥指纹 / Key: ${trust.active_kid}`;
    }, "rd-host-error");
    $("rd-host-trust-confirm").onchange = () => { $("rd-host-enroll-submit").disabled = !remoteHostTrust || !$("rd-host-trust-confirm").checked; };
    $("rd-host-enroll").onsubmit = event => {
      event.preventDefault();
      if (!remoteHostTrust || !$("rd-host-trust-confirm").checked) return;
      return runAction($("rd-host-enroll-submit"), async () => {
        const body = {username:$("rd-host-user").value,password:$("rd-host-password").value,mfa_code:$("rd-host-mfa").value,trust_pin:remoteHostTrust.trust_pin};
        $("rd-host-password").value = ""; $("rd-host-mfa").value = "";
        try { await remoteHostAction("enroll", body); }
        finally { body.password = ""; body.mfa_code = ""; }
      }, "rd-host-error");
    };
    setInterval(() => { if (!document.hidden) void refreshRemoteHost(); }, 3000);
    api("/local/state").then((state) => { if (state.enrolled) return showHome(); }).catch(() => { $("login-error").textContent = t("failed"); });

    setInterval(() => { if (!document.hidden) showHome(true).catch(() => { $("status").textContent = t("stale"); }); }, 30000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) showHome(true).catch(() => { $("status").textContent = t("stale"); }); });
