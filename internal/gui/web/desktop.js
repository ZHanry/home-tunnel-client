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
        welcomeTitle: "连接你的电脑，也连接你的世界。",
        welcomeDetail: "远程协助和内网服务，在一个地方管理。",
        stepSignIn: "登录并登记本机",
        stepService: "选择想要发布的本地服务",
        stepShare: "复制地址，随时访问",
        connectComputer: "欢迎回来",
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
        loginLead: "登录后管理设备、远控与内网服务。",
        server: "服务器地址", username: "用户名", password: "密码", newPassword: "请设置新密码（至少 12 个字符）", confirmPassword: "确认新密码", showPassword: "显示", hidePassword: "隐藏", working: "处理中…", failed: "操作失败，请重试", stale: "连接中断，显示缓存。请检查网络并重试。", synced: "最近同步", retryLatest: "读取最新版本并保留输入", conflict: "这条连接已在其他地方修改。请读取最新版本后核对并重新保存。",
        login: "登录并继续", quitApp: "退出程序", sync: "刷新", add: "新建连接",
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
        welcomeTitle: "Connect your computer and your world.",
        welcomeDetail: "Remote assistance and private services in one place.",
        stepSignIn: "Sign in and register this computer",
        stepService: "Choose a local service",
        stepShare: "Copy its address and connect anywhere",
        connectComputer: "Welcome back",
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
        loginLead: "Sign in to manage devices, remote sessions, and private services.",
        server: "Server URL", username: "Username", password: "Password", newPassword: "New password (at least 12 characters)", confirmPassword: "Confirm password", showPassword: "Show", hidePassword: "Hide", working: "Working…", failed: "Operation failed. Retry.", stale: "Connection interrupted. Showing cached data. Check your network and retry.", synced: "Last synced", retryLatest: "Load latest version and keep inputs", conflict: "This connection was edited elsewhere. Load the latest version and review before saving.",
        login: "Sign in and continue", quitApp: "Quit", sync: "Refresh", add: "New connection",
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
    const visualStyles = document.createElement("link");
    visualStyles.rel = "stylesheet";
    visualStyles.href = "/desktop.css";
    document.head.append(visualStyles);
    const sidebarBrand = document.querySelector(".sidebar-brand");
    sidebarBrand.innerHTML = '<img src="/HomeTunnel.svg" width="36" height="36" alt=""><span>home<span>tunnel</span><small>DESKTOP</small></span>';
    $("home").querySelector(".workspace-title .eyebrow").textContent = "NETWORK TUNNELS / 内网穿透";
    const navPaths = {
      "nav-remote": '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/>',
      "nav-devices": '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
      "nav-tunnels": '<circle cx="5" cy="6" r="2"/><circle cx="19" cy="18" r="2"/><path d="M7 6h7a4 4 0 0 1 0 8H9a4 4 0 0 0 0 8h8"/>',
      "nav-updates": '<path d="M12 3v12m-4-4 4 4 4-4M4 18v3h16v-3"/>',
      "nav-settings": '<circle cx="12" cy="12" r="3"/><path d="M19 12a7 7 0 0 0-.1-1.1l2-1.5-2-3.5-2.4 1a7 7 0 0 0-1.9-1.1L14.2 3h-4.4l-.4 2.8a7 7 0 0 0-1.9 1.1l-2.4-1-2 3.5 2 1.5a7 7 0 0 0 0 2.2l-2 1.5 2 3.5 2.4-1a7 7 0 0 0 1.9 1.1l.4 2.8h4.4l.4-2.8a7 7 0 0 0 1.9-1.1l2.4 1 2-3.5-2-1.5A7 7 0 0 0 19 12Z"/>',
      "nav-console": '<path d="M7 17 17 7M8 7h9v9M5 5h6M5 5v14h14v-6"/>'
    };
    const actionPaths = {
      copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
      more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
      arrow: '<path d="M5 12h14m-6-6 6 6-6 6"/>',
      external: '<path d="M7 17 17 7M8 7h9v9M5 5h6M5 5v14h14v-6"/>',
      plus: '<path d="M12 5v14M5 12h14"/>',
      search: '<circle cx="10.8" cy="10.8" r="6.8"/><path d="m16 16 5 5"/>',
      refresh: '<path d="M20 6v5h-5M4 18v-5h5M5.5 9A7 7 0 0 1 18 6l2 5M4 13l2 5a7 7 0 0 0 12.5-3"/>'
    };
    const actionIcon = (name) => `<svg viewBox="0 0 24 24" aria-hidden="true">${actionPaths[name]}</svg>`;
    for (const [id, paths] of Object.entries(navPaths)) {
      $(id).querySelector("span").innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${paths}</svg>`;
    }
    $("home").querySelector(".filter-bar").append($("refresh"));
    $("service-search").insertAdjacentHTML("beforebegin", actionIcon("search"));
    for (const [id, icon] of [["remote-refresh", "refresh"], ["devices-refresh", "refresh"]]) $(id).insertAdjacentHTML("afterbegin", actionIcon(icon));
    const updateDot = document.createElement("i");
    updateDot.className = "nav-update-dot";
    updateDot.hidden = true;
    updateDot.setAttribute("aria-hidden", "true");
    $("nav-updates").append(updateDot);
    function setUpdateAvailable(result) {
      updateDot.hidden = !result.newer;
      $("nav-updates").setAttribute("aria-label", result.newer ? `软件更新：发现正式版 ${result.latest}` : "软件更新");
    }
    const remoteTabs = document.createElement("div");
    remoteTabs.className = "remote-tabs";
    remoteTabs.innerHTML = '<button type="button" class="active" data-remote-tab="quick">快速连接</button><button type="button" data-remote-tab="unattended">无人值守</button>';
    const remoteQuick = document.createElement("div");
    remoteQuick.className = "remote-quick";
    const remoteOverview = document.createElement("div");
    remoteOverview.className = "remote-overview";
    remoteOverview.innerHTML = '<article class="settings-card remote-intro-card remote-connect-card"><div class="remote-card-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12h16m-6-6 6 6-6 6"/></svg></div><h3>连接远程电脑</h3><p>输入同账号设备标识，或选择在线设备。</p><form id="remote-connect-form" class="remote-manual"><label for="remote-device-id">设备标识</label><div class="remote-manual-row"><input id="remote-device-id" type="text" autocomplete="off" spellcheck="false" placeholder="粘贴设备标识" maxlength="36" required><button type="submit">开始连接</button></div></form><div id="remote-connect-list" class="remote-connect-list"></div><div class="remote-connect-actions"><button type="button" id="remote-open-assist" class="secondary">连接其他账号</button><button type="button" id="remote-open-console" class="secondary">打开网页远控</button></div></article>';
    remoteOverview.querySelector("#remote-open-console").insertAdjacentHTML("beforeend", actionIcon("external"));
    const hostCard = $("remote-host-card");
    hostCard.classList.add("remote-local-card");
    hostCard.querySelector("p.muted").textContent = "在本机批准单次授权后，绑定的会话自动启动；你可随时断开或撤销。";
    hostCard.insertAdjacentHTML("afterbegin", '<div class="remote-card-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/></svg></div>');
    hostCard.querySelector("h3").textContent = "允许对方连接这台电脑";
    hostCard.querySelector("p.muted").textContent = "由本机处理会话授权，你可以随时断开。";
    const hostIdentity = document.createElement("div");
    hostIdentity.className = "remote-host-identity";
    hostIdentity.innerHTML = '<span>本机设备标识</span><button type="button" id="rd-host-copy" class="secondary" disabled aria-label="复制本机设备标识"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/></svg></button>';
    hostCard.querySelector("#rd-host-detail").before(hostIdentity);
    const remoteAssistCard = document.createElement("article");
    remoteAssistCard.className = "settings-card remote-assist-card";
    remoteAssistCard.innerHTML = '<div class="remote-card-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a4 4 0 0 1 8 0v2M8 14h8"/></svg></div><h3>临时协助</h3><p>给其他账号提供一次性设备 ID 和临时密码。密码 5 分钟有效，使用一次即失效。</p><button type="button" id="rd-assist-create" disabled>生成临时密码</button><div id="rd-assist-secret" class="remote-assist-secret hidden"></div><div id="rd-assist-list"></div><p id="rd-assist-error" class="error" role="alert"></p>';
    const remoteSecurity = document.createElement("article");
    remoteSecurity.className = "settings-card remote-security-card";
    remoteSecurity.innerHTML = '<h3>授权与会话</h3><p>首次启用需核对服务器身份；进行中的会话可在这里立即撤销。</p>';
    for (const id of ["rd-host-enroll", "rd-host-pending", "rd-host-grants", "rd-host-files", "rd-host-error"]) remoteSecurity.append($(id));
    const hostMfaField = remoteSecurity.querySelector("#rd-host-mfa");
    const hostMfaLabel = remoteSecurity.querySelector('label[for="rd-host-mfa"]');
    hostMfaField.classList.add("hidden");
    hostMfaLabel.classList.add("hidden");
    remoteSecurity.querySelector("#rd-host-user").addEventListener("input", () => {
      hostMfaField.value = "";
      hostMfaField.classList.add("hidden");
      hostMfaLabel.classList.add("hidden");
    });
    remoteOverview.prepend(hostCard);
    remoteOverview.append(remoteAssistCard);
    remoteQuick.append(remoteOverview, remoteSecurity);
    const recentDevices = document.createElement("section");
    recentDevices.className = "recent-devices";
    recentDevices.innerHTML = '<div class="recent-devices-heading"><div><h2>最近设备</h2><p>从已登记设备快速进入</p></div><button type="button" id="remote-all-devices" class="secondary">查看所有设备</button></div><div id="recent-devices-list" class="recent-devices-list"></div>';
    recentDevices.querySelector("#remote-all-devices").insertAdjacentHTML("beforeend", actionIcon("arrow"));
    remoteQuick.append(recentDevices);
    const remoteUnattended = document.createElement("article");
    remoteUnattended.className = "settings-card remote-unattended hidden";
    remoteUnattended.innerHTML = '<div class="remote-card-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 5v2"/></svg></div><h2>连接这台电脑</h2><p>三种方式：收到连接请求后批准、设置固定密码自动连接、生成一次性临时密码。</p><div class="remote-access-identity"><span>跨账号设备 ID</span><strong id="rd-access-device-id">尚未创建</strong><button type="button" id="rd-access-create" class="secondary">创建设备 ID</button></div><div class="remote-fixed-password"><h3>固定密码</h3><p>知道设备 ID 和固定密码、且登录同一服务器的用户都可以连接。修改或关闭会撤销旧授权。</p><form id="rd-fixed-form"><label for="rd-fixed-password">新固定密码（至少 12 位）</label><div class="remote-manual-row"><input id="rd-fixed-password" type="password" autocomplete="new-password" minlength="12" maxlength="128" required><button type="submit" id="rd-fixed-save">保存密码</button></div></form><p id="rd-fixed-status" class="muted"></p><button type="button" id="rd-fixed-disable" class="danger" disabled>关闭固定密码</button></div><div class="remote-access-requests"><h3>待批准的连接请求</h3><div id="rd-access-requests"></div></div><div class="remote-hotkey-setting"><label for="rd-emergency-key">强制断开快捷键</label><select id="rd-emergency-key"><option value="X">Ctrl + Alt + Shift + X</option><option value="Q">Ctrl + Alt + Shift + Q</option><option value="F12">Ctrl + Alt + Shift + F12</option></select><p>按下后立即停止本机远控并关闭远控开关；重新启用需回到本页面。</p></div><div class="remote-unattended-actions"><span id="rd-unattended-status" class="state-badge">未启用</span><button type="button" id="rd-unattended-enable" disabled>开启高权限服务</button><button type="button" id="rd-unattended-disable" class="danger" disabled>关闭高权限服务</button></div><p id="rd-unattended-detail"></p><p id="rd-unattended-error" class="error" role="alert"></p>';
    $("remote-page").append(remoteTabs, remoteQuick, remoteUnattended);
    remoteTabs.querySelectorAll("button").forEach((button) => { button.onclick = () => {
      const unattended = button.dataset.remoteTab === "unattended";
      remoteQuick.classList.toggle("hidden", unattended);
      remoteUnattended.classList.toggle("hidden", !unattended);
      remoteTabs.querySelectorAll("button").forEach((tab) => tab.classList.toggle("active", tab === button));
    }; });
    $("rd-host-copy").onclick = () => navigator.clipboard.writeText($("rd-host-detail").textContent).catch(() => {});
    $("remote-all-devices").onclick = () => void showDevices();
    const updateLayout = document.createElement("div");
    updateLayout.className = "update-layout";
    const updateCard = $("update-page").querySelector(".settings-card");
    $("update-page").querySelector("h1").textContent = "保持应用最新";
    updateCard.classList.add("update-hero-card");
    updateCard.insertAdjacentHTML("afterbegin", '<span class="update-logo"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12m-4-4 4 4 4-4M4 18v3h16v-3"/></svg></span><span class="state-badge update-version-badge">当前版本 · <span id="update-version-badge">—</span></span>');
    updateCard.querySelector("h3").textContent = "更新由你决定。";
    $("update-check").innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6v5h-5M4 18v-5h5M5.5 9A7 7 0 0 1 18 6l2 5M4 13l2 5a7 7 0 0 0 12.5-3"/></svg>检查正式版本';
    updateCard.before(updateLayout);
    updateLayout.append(updateCard);
    const updateNotes = document.createElement("article");
    updateNotes.className = "settings-card update-notes";
    updateNotes.innerHTML = '<h3>版本与安装</h3><p>当前版本 <strong id="update-current-version">—</strong></p><p>发现正式版后可下载并校验 SHA-256。安装前请退出正在进行的远控会话。</p><p>私有候选版本不会显示为公开更新。</p>';
    updateLayout.append(updateNotes);
    let locale = document.documentElement.lang === "en" ? "en" : "zh-CN";
    const t = (key) => (strings[locale] && strings[locale][key]) || strings["zh-CN"][key] || key;
    function applyLocale() {
      document.documentElement.lang = locale;
      document.querySelectorAll("[data-i18n]").forEach((node) => { node.textContent = t(node.dataset.i18n); });
      for (const [id, icon] of [["add", "plus"], ["refresh", "refresh"]]) $(id).insertAdjacentHTML("afterbegin", actionIcon(icon));
      $("service-search").placeholder = t("searchServices");
      $("locale-toggle").textContent = locale === "en" ? "中" : "EN";
      try { localStorage.setItem("ht_locale", locale); } catch (e) {}
    }
    function applyTheme(theme) {
      document.documentElement.dataset.theme = theme;
      document.documentElement.style.colorScheme = theme;
      const icon = theme === "dark"
        ? '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
        : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20.5 14.2A8.5 8.5 0 0 1 9.8 3.5 8.5 8.5 0 1 0 20.5 14.2Z"/></svg>';
      for (const id of ["theme-toggle", "sidebar-theme"]) {
        $(id).innerHTML = icon;
        $(id).setAttribute("aria-label", theme === "dark" ? "切换至浅色主题" : "切换至深色主题");
      }
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
    let accountDevices = [];
    let localDeviceID = "";
    async function openDeviceRemote(device) {
      if (!consoleUrl || !device?.id) return;
      const error = $("remote-page").classList.contains("hidden") ? $("devices-error") : $("remote-open-error");
      error.textContent = "";
      try { await api("/local/remote/window", { method: "POST", body: JSON.stringify({ device_id: device.id }) }); }
      catch (failure) { error.textContent = failure.message; }
    }
    function createDeviceCard(device, compact = false) {
      const card = document.createElement("article");
      card.className = compact ? "recent-device-card" : "account-device-card";
      const icon = document.createElement("span");
      icon.className = "account-device-icon";
      icon.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/></svg>';
      const details = document.createElement("div");
      details.className = "account-device-details";
      const name = document.createElement("strong");
      name.textContent = device.name || t("unnamedComputer");
      const status = document.createElement("small");
      const online = device.status === "active" && device.online;
      status.textContent = `${device.id === localDeviceID ? "本机 · " : ""}${online ? "在线" : "离线"} · ${device.id || "—"}`;
      details.append(name, status);
      const action = document.createElement("button");
      action.type = "button";
      action.className = "secondary";
      action.textContent = compact ? "查看设备" : "远程控制";
      action.insertAdjacentHTML("beforeend", actionIcon(compact ? "arrow" : "external"));
      action.disabled = !compact && (!online || !consoleUrl);
      action.onclick = compact ? () => void showDevices() : () => void openDeviceRemote(device);
      card.append(icon, details, action);
      return card;
    }
    function renderAccountDevices() {
      const filtered = accountDevices.filter((device) => `${device.name || ""} ${device.id || ""}`.toLocaleLowerCase().includes($("devices-search").value.trim().toLocaleLowerCase()));
      $("devices-count").textContent = `${filtered.length} 台设备`;
      $("devices-list").replaceChildren(...filtered.map((device) => createDeviceCard(device)));
      if (!filtered.length) $("devices-list").textContent = accountDevices.length ? "没有匹配的设备" : "还没有登记设备";
      const recent = accountDevices.filter((device) => device.id !== localDeviceID).slice(0, 3);
      $("recent-devices-list").replaceChildren(...recent.map((device) => createDeviceCard(device, true)));
      if (!recent.length) $("recent-devices-list").textContent = "还没有其他已登记设备";
      const connect = accountDevices.filter((device) => device.id !== localDeviceID && device.status === "active" && device.online).slice(0, 2);
      $("remote-connect-list").replaceChildren(...connect.map((device) => {
        const row = document.createElement("button");
        row.type = "button";
        row.className = "secondary remote-connect-device";
        row.disabled = !consoleUrl;
        const name = document.createElement("strong");
        name.textContent = device.name || t("unnamedComputer");
        const hint = document.createElement("span");
        hint.textContent = "远程控制";
        hint.insertAdjacentHTML("beforeend", actionIcon("external"));
        row.append(name, hint);
        row.onclick = () => void openDeviceRemote(device);
        return row;
      }));
      if (!connect.length) $("remote-connect-list").textContent = "当前没有在线的其他设备";
    }
    async function loadDevices() {
      const result = await api("/local/devices");
      accountDevices = (result.items || []).sort((left, right) => Number(right.online) - Number(left.online));
      localDeviceID = result.local_device_id || "";
      renderAccountDevices();
    }
    $("rd-host-enable").textContent = "允许远程连接";
    $("rd-host-disable").textContent = "关闭远程连接";
    $("rd-host-stop").textContent = "立即断开";
    $("remote-connect-form").onsubmit = (event) => {
      event.preventDefault();
      const id = $("remote-device-id").value.trim().toLowerCase();
      const device = accountDevices.find((item) => item.id?.toLowerCase() === id);
      if (!device || device.id === localDeviceID || device.status !== "active" || !device.online) {
        $("remote-open-error").textContent = "同账号设备未找到或当前离线";
        return;
      }
      if (!consoleUrl) {
        $("remote-open-error").textContent = "网页远控当前不可用";
        return;
      }
      void openDeviceRemote(device);
    };
    $("remote-open-console").onclick = () => { if (consoleUrl) window.open(consoleUrl.replace(/\/$/, "") + "/admin#remote", "_blank", "noopener,noreferrer"); };
    $("remote-open-assist").onclick = async () => {
      $("remote-open-error").textContent = "";
      try { await api("/local/remote/window", {method:"POST", body:JSON.stringify({assist:true})}); }
      catch (error) { $("remote-open-error").textContent = error.message; }
    };
    function selectNavigation(name) {
      document.body.classList.add("workspace-active");
      $("app-sidebar").classList.remove("hidden");
      for (const item of ["remote", "devices", "tunnels", "updates", "settings"])
        $("nav-" + item).classList.toggle("active", item === name);
    }
    function hideWorkspacePages() {
      for (const item of ["login", "home", "settings", "editor", "remote-page", "devices-page", "update-page"])
        $(item).classList.add("hidden");
    }
    let navigationRevision = 0;
    async function showRemote() {
      const revision = ++navigationRevision;
      const state = await api("/local/state");
      if (revision !== navigationRevision) return;
      if (!state.enrolled) {
        document.body.classList.remove("workspace-active");
        $("app-sidebar").classList.add("hidden");
        hideWorkspacePages();
        $("login").classList.remove("hidden");
        return;
      }
      hideWorkspacePages();
      $("remote-page").classList.remove("hidden");
      selectNavigation("remote");
      consoleUrl = state.console_url || "";
      $("sidebar-machine").textContent = state.device_name || t("unnamedComputer");
      $("sidebar-status").textContent = state.stale ? t("stale") : t(state.agent_state === "Online" ? "agentOnline" : "agentOffline");
      void refreshRemoteHost();
      void loadDevices().catch(() => { $("recent-devices-list").textContent = "设备列表暂不可用"; });
    }
    async function showDevices() {
      const revision = ++navigationRevision;
      const state = await api("/local/state");
      if (revision !== navigationRevision) return;
      if (!state.enrolled) { hideWorkspacePages(); $("login").classList.remove("hidden"); $("app-sidebar").classList.add("hidden"); document.body.classList.remove("workspace-active"); return; }
      consoleUrl = state.console_url || "";
      hideWorkspacePages();
      $("devices-page").classList.remove("hidden");
      selectNavigation("devices");
      $("devices-error").textContent = "";
      try { await loadDevices(); } catch (error) { $("devices-error").textContent = error.message; }
    }
    async function showUpdates() {
      ++navigationRevision;
      hideWorkspacePages();
      $("update-page").classList.remove("hidden");
      selectNavigation("updates");
      await checkUpdates();
    }
    async function checkUpdates() {
      const status = $("update-page-status");
      status.textContent = locale === "en" ? "Checking…" : "正在检查…";
      try {
        const result = await api("/local/update");
        setUpdateAvailable(result);
        $("update-current-version").textContent = result.current || "—";
        $("update-version-badge").textContent = result.current || "—";
        status.replaceChildren();
        status.append(result.newer ? `${t("updatePrefix")}${result.latest}${t("updateCurrent")}${result.current}${t("updateSuffix")}` : (locale === "en" ? "No newer stable release." : "当前没有更新的正式版本。"));
        if (result.newer && result.download_url) {
          const download = document.createElement("button");
          download.type = "button";
          download.textContent = t("download");
          download.onclick = async () => {
            download.disabled = true;
            try {
              const packageResult = await api("/local/update/download", { method: "POST" });
              if (packageResult.verified !== true) throw new Error("更新包未通过 SHA-256 校验 / Update verification failed");
              status.textContent = packageResult.hint || packageResult.path;
            } catch (error) { status.textContent = error.message; }
          };
          status.append(" ", download);
        }
        if (result.newer && result.url) {
          const link = document.createElement("a");
          link.href = result.url;
          link.target = "_blank";
          link.rel = "noreferrer";
          link.textContent = " " + t("openRelease");
          status.append(link);
        }
      } catch (error) { status.textContent = error.message; }
    }
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
      const isSelect = button.tagName === "SELECT";
      const content = isSelect ? null : [...button.childNodes]; button.disabled = true;
      if (!isSelect) button.textContent = t("working");
      try { await action(); } catch (error) { $(errorId).textContent = error.message || t("failed"); }
      finally { if (button.isConnected) { button.disabled = false; if (content) button.replaceChildren(...content); } }
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
      if (refreshing || background && (!$("editor").classList.contains("hidden") || !$("login").classList.contains("hidden") || !$("settings").classList.contains("hidden") || !$("remote-page").classList.contains("hidden") || !$("devices-page").classList.contains("hidden") || !$("update-page").classList.contains("hidden"))) return;
      const revision = background ? navigationRevision : ++navigationRevision;
      refreshing = true;
      try {
      $("settings").classList.add("hidden");
      $("login").classList.add("hidden");
      $("editor").classList.add("hidden");
      $("remote-page").classList.add("hidden");
      $("devices-page").classList.add("hidden");
      $("update-page").classList.add("hidden");
      $("home").classList.remove("hidden");
      const state = await api("/local/state");
      if (revision !== navigationRevision) return;
      consoleUrl = state.console_url || "";
      capabilities = state.capabilities || {}; serverStale = Boolean(state.stale);
      if (!state.enrolled) { $("home").classList.add("hidden"); $("login").classList.remove("hidden"); $("app-sidebar").classList.add("hidden"); document.body.classList.remove("workspace-active"); return; }
      selectNavigation("tunnels");
	  void refreshRemoteHost();
      $("machine-name").textContent = state.device_name || t("unnamedComputer");
      $("sidebar-machine").textContent = state.device_name || t("unnamedComputer");
      $("machine-version").textContent = "Home Tunnel " + (state.version || "8.0.0");
      $("settings-server").textContent = consoleUrl;
      $("count-total").textContent = (state.connections || []).length;
      $("count-online").textContent = (state.connections || []).filter(c => c.enabled && c.state === "Online").length;
      $("count-paused").textContent = (state.connections || []).filter(c => !c.enabled).length;
      $("status").textContent = state.stale ? t("stale") : `${t(state.agent_state === "Online" ? "agentOnline" : state.agent_state === "Starting" ? "agentStarting" : "agentOffline")} · ${t("synced")} ${new Date(state.last_synced_at || Date.now()).toLocaleTimeString(locale)}`;
      $("sidebar-status").textContent = $("status").textContent;
      if (Date.now() - lastUpdateCheck > 3600000) {
      lastUpdateCheck = Date.now();
      $("update").replaceChildren();
      void (async () => { try {
        const update = await api("/local/update");
        setUpdateAvailable(update);
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
      $("connections").innerHTML = items.length ? '<div class="service-list-head"><span>连接名称</span><span>公网地址</span><span>本地目标</span><span>状态</span><span>操作</span></div>' + items.map(item => {
        const publicUrl = item.public_url || item.access_url || item.public_endpoint || "";
        const status = !item.enabled ? t("paused") : item.state === "Online" ? t("online") : item.state || "—";
        return `<article class="service-row"><div class="service-identity"><input type="checkbox" class="batch-select" data-select="${escapeHtml(item.id)}" aria-label="${escapeHtml(t("select") + ": " + item.name)}" ${selectedConnections.has(item.id) ? "checked" : ""}><span class="service-protocol">${escapeHtml((item.application_protocol || item.proxy_type || "http").toUpperCase())}</span><div><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml((item.application_protocol || item.proxy_type || "http").toUpperCase())} ${escapeHtml(t("connectionType"))}</small></div></div><button type="button" class="url" data-copy="${escapeHtml(publicUrl)}" aria-label="${escapeHtml(t("copyAddress"))}">${escapeHtml(publicUrl || item.subdomain)}</button><span class="service-target">${escapeHtml(item.local_host)}:${escapeHtml(item.local_port)}</span><span class="state-badge ${item.enabled && item.state === "Online" ? "online" : ""}">${escapeHtml(status)}</span><div class="actions"><button class="secondary" data-edit="${escapeHtml(item.id)}" aria-label="${escapeHtml(t("edit") + ": " + item.name)}"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19 12a7 7 0 0 0-.1-1.1l2-1.5-2-3.5-2.4 1a7 7 0 0 0-1.9-1.1L14.2 3h-4.4l-.4 2.8a7 7 0 0 0-1.9 1.1l-2.4-1-2 3.5 2 1.5a7 7 0 0 0 0 2.2l-2 1.5 2 3.5 2.4-1a7 7 0 0 0 1.9 1.1l.4 2.8h4.4l.4-2.8a7 7 0 0 0 1.9-1.1l2.4 1 2-3.5-2-1.5A7 7 0 0 0 19 12Z"/></svg></button><button class="secondary" data-toggle="${escapeHtml(item.id)}" data-enabled="${item.enabled}" aria-label="${escapeHtml(t(item.enabled ? "pause" : "enable") + ": " + item.name)}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="${item.enabled ? "M6 5v14M12 5v14" : "M7 4v16l13-8Z"}"/></svg></button><details><summary aria-label="${escapeHtml(t("more") + ": " + item.name)}">⋯</summary><button class="danger" data-delete="${escapeHtml(item.id)}">${escapeHtml(t("remove"))}</button></details></div></article>`;
      }).join("") : `<div class="empty-state"><strong>${escapeHtml(t(items.length || connections.length ? "noMatch" : "empty"))}</strong>${!connections.length ? `<button id="empty-add">${escapeHtml(t("add"))}</button>` : ""}</div>`;
      $("connections").querySelectorAll(".service-row").forEach((row) => {
        const address = row.querySelector(".url");
        const copy = document.createElement("button");
        copy.type = "button";
        copy.className = "secondary";
        copy.dataset.copy = address.dataset.copy;
        copy.setAttribute("aria-label", address.getAttribute("aria-label"));
        copy.disabled = !address.dataset.copy;
        copy.innerHTML = actionIcon("copy");
        row.querySelector(".actions").prepend(copy);
        row.querySelector(".actions summary").innerHTML = actionIcon("more");
      });
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
        ++navigationRevision;
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
      ++navigationRevision;
      hideWorkspacePages(); $("settings").classList.remove("hidden"); selectNavigation("settings");
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
      $("mfa-step").classList.add("hidden");
      $("mfa-code").required = false;
      $("new-password").value = $("confirm-password").value = "";
      $("password-change").classList.add("hidden");
    };
    for (const field of ["server", "username", "password"]) {
      $(field).addEventListener("input", () => {
        $("mfa-code").value = "";
        $("mfa-code").required = false;
        $("mfa-step").classList.add("hidden");
      });
    }
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
        $("mfa-step").classList.add("hidden");
        $("mfa-code").required = false;
        await showRemote();
      } catch (error) {
        if (error.code === "MFA_REQUIRED" || error.code === "MFA_INVALID") {
          $("mfa-step").classList.remove("hidden"); $("mfa-code").required = true; $("mfa-code").focus();
          $("login-error").textContent = error.message;
        } else if (/requires a password change|PASSWORD_CHANGE_REQUIRED/.test(error.message)) {
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
    $("add").onclick = () => { ++navigationRevision; resetEditor(); $("home").classList.add("hidden"); $("editor").classList.remove("hidden"); selectNavigation("tunnels"); };
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
    let remoteHostLoading = false, remoteHostTrust = null, remoteHostListSignature = "", remoteFileSignature = "", remoteHostGeneration = 0, assistSecret = null, lastAssistInvites = [];
    let remoteHostAbort = new AbortController();
    function resetRemoteHostUI() {
      remoteHostGeneration++; remoteHostAbort.abort(); remoteHostAbort = new AbortController();
      remoteHostTrust = null; remoteHostListSignature = ""; remoteFileSignature = "";
      assistSecret = null; lastAssistInvites = [];
      $("rd-assist-secret").replaceChildren(); $("rd-assist-list").replaceChildren(); $("rd-assist-error").textContent = "";
      $("rd-assist-create").disabled = true;
      $("rd-host-password").value = ""; $("rd-host-mfa").value = ""; $("rd-host-trust").textContent = "";
      hostMfaField.classList.add("hidden"); hostMfaLabel.classList.add("hidden");
      $("rd-host-trust-confirm").checked = false; $("rd-host-enroll-submit").disabled = true;
      $("rd-host-pending").replaceChildren(); $("rd-host-grants").replaceChildren();
      $("rd-host-files").replaceChildren();
      $("rd-unattended-error").textContent = "";
      for (const id of ["enable", "disable", "stop"]) $("rd-host-" + id).disabled = true;
      for (const id of ["enable", "disable"]) $("rd-unattended-" + id).disabled = true;
    }
    const remotePermissionNames = {
      view: "屏幕 / Screen", "input.keyboard": "键盘 / Keyboard", "input.pointer": "鼠标 / Pointer", "input.text": "文字输入 / Text input",
      "audio.system": "系统声音 / System audio", "audio.microphone": "麦克风回传 / Microphone", "clipboard.read": "读取本机剪贴板 / Read local clipboard",
      "clipboard.write": "写入本机剪贴板 / Write local clipboard", "files.send": "发送文件到本机 / Send files here", "files.receive": "从本机接收文件 / Receive files"
    };
    async function remoteHostAction(action, extra = {}) {
      try {
        const result = await api("/local/remote/action", { method: "POST", body: JSON.stringify({ action, ...extra }), signal:remoteHostAbort.signal });
        if (action === "disable") { assistSecret = null; renderAssistInvites([]); }
        return result;
      }
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
          const mode = document.createElement("p"); mode.textContent = event.mode === "persistent" ? "管理员批准后绑定为可信设备，持续授权最长 30 天" : "仅本次会话 / This session only"; box.append(mode);
          const data = {id:event.id,kind:event.kind,permissions:event.permissions,mode:event.mode,connection_epoch:event.connection_epoch,state_version:event.state_version};
          actions.append(remoteActionButton(event.mode === "persistent" && event.kind === "pairing" ? "管理员信任此设备" : "允许以上权限 / Allow listed permissions", "approve", data), remoteActionButton("拒绝 / Reject", "reject", data, true));
          box.append(actions);
        }
        $("rd-host-pending").append(box);
      }
      for (const grant of state.grants || []) {
        if (grant.revoked || Date.parse(grant.expires_at) <= Date.now()) continue;
        const row = document.createElement("div"), detail = document.createElement("p"); row.className = "settings-card";
        detail.textContent = `${grant.mode === "persistent" ? "可信设备 · " : "单次授权 · "}${grant.controller_endpoint_id} · ${(grant.permissions || []).map(name => remotePermissionNames[name] || name).join(" · ")} · ${new Date(grant.expires_at).toLocaleString(locale)}`;
        detail.style.overflowWrap = "anywhere";
        row.append(detail, remoteActionButton("撤销授权并断开 / Revoke and disconnect", "revoke", {id:grant.id}, true)); $("rd-host-grants").append(row);
      }
    }
    function renderAssistInvites(invites) {
      lastAssistInvites = invites || [];
      const secretBox = $("rd-assist-secret"); secretBox.replaceChildren();
      if (assistSecret && Date.parse(assistSecret.expires_at) > Date.now() && !lastAssistInvites.some(item => item.id === assistSecret.id && item.state !== "active")) {
        secretBox.classList.remove("hidden");
        const heading = document.createElement("strong"); heading.textContent = "仅本次显示，请安全地发送给对方";
        const code = document.createElement("p"); code.textContent = `设备 ID：${assistSecret.device_id}`;
        const password = document.createElement("p"); password.textContent = `临时密码：${assistSecret.temporary_password}`;
        const copy = document.createElement("button"); copy.type = "button"; copy.className = "secondary"; copy.textContent = "复制协助信息";
        copy.onclick = () => navigator.clipboard.writeText(`设备 ID：${assistSecret.device_id}\n临时密码：${assistSecret.temporary_password}`).catch(() => {});
        secretBox.append(heading, code, password, copy);
      } else { assistSecret = null; secretBox.classList.add("hidden"); }
      const list = $("rd-assist-list"); list.replaceChildren();
      for (const invite of lastAssistInvites) {
        const row = document.createElement("div"); row.className = "remote-assist-invite";
        const detail = document.createElement("span"); detail.textContent = `${invite.device_id} · ${invite.state === "redeemed" ? "已使用" : "等待连接"} · ${new Date(invite.expires_at).toLocaleString(locale)}`;
        const revoke = document.createElement("button"); revoke.type = "button"; revoke.className = "danger"; revoke.textContent = "撤销";
        revoke.onclick = () => runAction(revoke, async () => { await remoteHostAction("revoke_invite", {id:invite.id}); if (assistSecret?.id === invite.id) assistSecret = null; renderAssistInvites(lastAssistInvites.filter(item => item.id !== invite.id)); }, "rd-assist-error");
        row.append(detail, revoke); list.append(row);
      }
    }
    function renderAccessRequests(requests = []) {
      const list = $("rd-access-requests"); list.replaceChildren();
      if (!requests.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = "暂无请求"; list.append(empty); return; }
      for (const request of requests) {
        const row = document.createElement("div"), detail = document.createElement("div"), actions = document.createElement("div");
        row.className = "remote-access-request"; actions.className = "remote-access-request-actions";
        const name = document.createElement("strong"), expiry = document.createElement("small");
        name.textContent = request.controller_endpoint_id; expiry.textContent = `有效至 ${new Date(request.expires_at).toLocaleTimeString(locale)}`;
        detail.append(name, expiry);
        const approve = document.createElement("button"), reject = document.createElement("button");
        approve.type = reject.type = "button"; approve.textContent = "批准本次连接"; reject.textContent = "拒绝"; reject.className = "danger";
        approve.onclick = () => runAction(approve, () => remoteHostAction("approve_access_request", { id: request.id }), "rd-unattended-error");
        reject.onclick = () => runAction(reject, () => remoteHostAction("reject_access_request", { id: request.id }), "rd-unattended-error");
        actions.append(approve, reject); row.append(detail, actions); list.append(row);
      }
    }
    function renderRemoteFiles(files = {}) {
      const signature = JSON.stringify(files);
      if (signature === remoteFileSignature) return;
      remoteFileSignature = signature;
      const container = $("rd-host-files"); container.replaceChildren();
      if (!files.session_id || !files.can_send && !files.can_receive) return;
      const title = document.createElement("h3"), help = document.createElement("p");
      title.textContent = "会话文件 / Session files";
      help.textContent = "文件通过当前直连传输。请先在控制端开启文件权限；本机选择文件或保存位置，不覆盖已有文件。 / Enable file transfer on the controller, then choose files or a new destination here.";
      container.append(title, help);
      const button = (label, action, id) => {
        const node = document.createElement("button"); node.type = "button"; node.className = "secondary"; node.textContent = label;
        node.onclick = () => runAction(node, async () => {
          try { await api("/local/remote/files", {method:"POST", body:JSON.stringify({action, id, session_id:files.session_id, connection_epoch:files.connection_epoch}), signal:remoteHostAbort.signal}); }
          finally { void refreshRemoteHost(); }
        }, "rd-host-error");
        return node;
      };
      if (files.can_send) container.append(button("选择多个文件发送 / Select files to send", "send"));
      for (const item of files.items || []) {
        const row = document.createElement("div"), detail = document.createElement("p"); row.className = "settings-card";
        const phases = {offer:"等待选择 / Awaiting selection", progress:"传输中 / Transferring", complete:"已完成 / Complete", cancelled:"已取消 / Cancelled", error:"传输失败 / Failed"};
        detail.textContent = `${item.name || "文件 / File"} · ${item.outgoing ? "发送 / Send" : "接收 / Receive"} · ${phases[item.event] || item.event} · ${item.offset || 0} / ${item.size || 0} bytes${item.error_code ? " · " + item.error_code : ""}`;
        detail.style.overflowWrap = "anywhere"; row.append(detail);
        if (item.may_be_saved) { const note = document.createElement("p"); note.textContent = "文件可能已保存，请检查目标文件夹。 / The file may have been saved; check the destination folder."; row.append(note); }
        if (item.event === "offer" && !item.outgoing && files.can_receive) row.append(button("选择保存位置 / Choose destination", "receive", item.id));
        if (["offer", "progress"].includes(item.event)) row.append(button("取消此文件 / Cancel file", "cancel", item.id));
        container.append(row);
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
        $("rd-host-status").textContent = !ready ? "此安装包没有可用的远控后端" : state.active_session_id ? "远程会话进行中" : state.enabled ? "已允许连接" : "远程连接已关闭";
        $("rd-host-detail").textContent = state.endpoint_id || state.error_code || "尚未登记";
        $("rd-host-copy").disabled = !state.endpoint_id;
        $("rd-host-enable").disabled = !ready || !state.enrolled || state.enabled && state.running;
        $("rd-host-disable").disabled = !state.enabled;
        $("rd-host-stop").disabled = !state.active_session_id;
        const unattendedSupported = state.capabilities?.unattended_enabled === true;
        $("rd-unattended-status").textContent = state.unattended_enabled ? "已开启" : "未启用";
        $("rd-unattended-detail").textContent = !unattendedSupported ? "当前版本尚不支持锁屏、登录前或 UAC 安全桌面远控；固定密码仅作用于已登录的桌面。" : state.unattended_enabled ? "高权限服务已开启。" : "需要本机管理员权限开启高权限服务。";
        $("rd-unattended-enable").disabled = !state.enrolled || !state.enabled || !unattendedSupported || state.unattended_enabled;
        $("rd-unattended-disable").disabled = !state.unattended_enabled;
        const access = state.access_profile || {};
		$("rd-emergency-key").value = state.emergency_key || "X";
        $("rd-access-device-id").textContent = access.device_id || "尚未创建";
        $("rd-access-create").disabled = !state.enrolled || !state.enabled || !state.running || !!access.device_id;
        $("rd-fixed-save").disabled = !state.enabled || !state.running || !ready;
        const fixedActive = !!access.fixed_password_enabled && access.revision === state.fixed_revision;
        $("rd-fixed-disable").disabled = !fixedActive;
        $("rd-fixed-status").textContent = fixedActive ? "固定密码已启用 · 可跨账号自动连接" : access.fixed_password_enabled ? "服务端密码与本机授权版本不一致，请重新设置" : "未设置固定密码";
        renderAccessRequests(state.access_requests);
        $("rd-assist-create").disabled = !state.enabled || !state.running || !state.enrolled || !ready;
        if (!state.enabled) assistSecret = null;
        $("rd-host-enroll").classList.toggle("hidden", !ready || state.enrolled);
        if (state.enrolled || !ready) {
          $("rd-host-password").value = ""; $("rd-host-mfa").value = "";
          hostMfaField.classList.add("hidden"); hostMfaLabel.classList.add("hidden");
        }
        renderRemoteApprovals(state);
        renderAssistInvites(state.invites);
        renderRemoteFiles(state.files);
        remoteSecurity.classList.toggle("hidden", !ready || state.enrolled && !$("rd-host-pending").childElementCount && !$("rd-host-grants").childElementCount && !$("rd-host-files").childElementCount && !$("rd-host-error").textContent);
        const count = (state.pending || []).filter(event => !event.display_code).length + (state.access_requests || []).length;
        $("settings-open").textContent = t("settings") + (count ? ` · ${count} 待批准 / pending` : "");
      } catch {
        if (generation !== remoteHostGeneration) return;
        $("rd-host-status").textContent = "无法读取远控状态 / Remote status unavailable";
        for (const id of ["enable", "disable", "stop"]) $("rd-host-" + id).disabled = id === "enable";
        for (const id of ["enable", "disable"]) $("rd-unattended-" + id).disabled = true;
      }
      finally { remoteHostLoading = false; }
    }
    for (const action of ["enable", "disable", "stop"]) $("rd-host-" + action).onclick = () => runAction($("rd-host-" + action), () => remoteHostAction(action), "rd-host-error");
    for (const action of ["enable", "disable"]) $("rd-unattended-" + action).onclick = () => runAction($("rd-unattended-" + action), () => remoteHostAction(action + "_unattended"), "rd-unattended-error");
    $("rd-access-create").onclick = () => runAction($("rd-access-create"), () => remoteHostAction("create_access_profile"), "rd-unattended-error");
    $("rd-fixed-form").onsubmit = event => {
      event.preventDefault();
      const password = $("rd-fixed-password").value;
      $("rd-fixed-password").value = "";
      return runAction($("rd-fixed-save"), () => remoteHostAction("set_fixed_password", { fixed_password: password }), "rd-unattended-error");
    };
    $("rd-fixed-disable").onclick = () => runAction($("rd-fixed-disable"), () => remoteHostAction("disable_fixed_password"), "rd-unattended-error");
    $("rd-emergency-key").onchange = () => runAction($("rd-emergency-key"), () => remoteHostAction("set_emergency_hotkey", { emergency_key: $("rd-emergency-key").value }), "rd-unattended-error");
    $("rd-assist-create").onclick = () => runAction($("rd-assist-create"), async () => {
      assistSecret = await remoteHostAction("create_invite");
      renderAssistInvites(lastAssistInvites);
    }, "rd-assist-error");
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
        catch (error) {
          if (error.code === "RD_MFA_REQUIRED" || error.code === "RD_MFA_INVALID") {
            hostMfaField.classList.remove("hidden");
            hostMfaLabel.classList.remove("hidden");
            hostMfaField.focus();
          }
          throw error;
        }
        finally { body.password = ""; body.mfa_code = ""; }
      }, "rd-host-error");
    };
    setInterval(() => { if (!document.hidden) void refreshRemoteHost(); }, 3000);
    $("nav-remote").onclick = () => showRemote().catch((error) => { $("rd-host-error").textContent = error.message; });
    $("nav-devices").onclick = () => showDevices().catch((error) => { $("devices-error").textContent = error.message; });
    $("nav-tunnels").onclick = () => showHome().catch((error) => { $("status").textContent = error.message; });
    $("nav-updates").onclick = () => showUpdates().catch((error) => { $("update-page-status").textContent = error.message; });
    $("nav-settings").onclick = () => $("settings-open").click();
    $("nav-console").onclick = () => { if (consoleUrl) window.open(consoleUrl, "_blank", "noopener,noreferrer"); };
    $("sidebar-locale").onclick = () => $("locale-toggle").click();
    $("sidebar-theme").onclick = () => $("theme-toggle").click();
    $("remote-refresh").onclick = () => void refreshRemoteHost();
    $("devices-refresh").onclick = () => void loadDevices().catch((error) => { $("devices-error").textContent = error.message; });
    $("devices-search").oninput = renderAccountDevices;
    $("update-check").onclick = () => void checkUpdates();
    api("/local/state").then((state) => { if (state.enrolled) return showRemote(); }).catch(() => { $("login-error").textContent = t("failed"); });

    setInterval(() => { if (!document.hidden) showHome(true).catch(() => { $("status").textContent = t("stale"); }); }, 30000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) showHome(true).catch(() => { $("status").textContent = t("stale"); }); });
