    const strings = {
      "zh-CN": { close: "关闭", renamePending: "正在保存，关闭窗口不会取消保存。", renameDevice: "重命名本机", renameDeviceHelp: "新名称会同步到你的设备列表，并在下次启动时保留。", selfConnection: "不能远程连接本机，请选择其他设备。", deviceRenamed: "设备名称已更新", select: "选择", batchPause: "暂停所选", batchResume: "恢复所选", tags: "设备标签（逗号分隔，最多 12 个）", favorite: "收藏此设备", metadata: "设备标记", saveMetadata: "保存标记", connectionType: "连接类型",
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
      en: { close: "Close", renamePending: "Saving. Closing this window will not cancel the save.", renameDevice: "Rename this device", renameDeviceHelp: "The new name syncs to your device list and stays after restarting.", selfConnection: "You cannot connect remotely to this computer. Choose another device.", deviceRenamed: "Device name updated", select: "Select", batchPause: "Pause selected", batchResume: "Resume selected", tags: "Device tags (comma separated, up to 12)", favorite: "Favorite this device", metadata: "Device organization", saveMetadata: "Save tags", connectionType: "Connection type",
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
    Object.assign(strings["zh-CN"], {
      wizardService: "设备与服务", wizardTarget: "本地目标", wizardAccess: "访问方式", wizardPublish: "检查并发布",
      serviceTemplate: "服务模板", typeHttps: "Web · 本地 HTTPS", checkTarget: "检查本地目标", ackTargetCheck: "我已了解检查结果，发布后会验证实际访问。",
      publicWebHelp: "公网使用服务器配置的 HTTPS 域名；本地 HTTP/HTTPS 在上一步选择。", reviewService: "核对服务配置", publishHelp: "发布后等待设备同步配置，再从外部网络验证访问。",
      connectionCreated: "连接已创建", publish: "发布服务", nextStep: "下一步", previousStep: "上一步", targetNotChecked: "先检查本地目标再继续。",
      TARGET_TCP_READY: "本地 TCP 端口可连接。应用登录与公网访问仍需验证。", TARGET_HTTP_READY: "本地 Web 服务已响应。应用登录与公网访问仍需验证。",
      TARGET_HTTP_UNHEALTHY: "本地 Web 服务返回服务器错误，请检查应用；可确认后继续配置。", TARGET_UNREACHABLE: "本地端口不可达，请启动服务并检查地址、端口与防火墙。",
      TARGET_HTTP_FAILED: "本地 Web 请求失败，请核对协议并检查服务。", TARGET_TLS_FAILED: "本地 HTTPS 证书或 TLS 握手无效，请修复后重试。",
      TARGET_INVALID: "本地主机或端口无效。请只填写主机，不要包含网址、路径或账号。", UDP_MANUAL_CHECK: "UDP 无法通过打开端口证明可达。发布后须从外部网络使用目标应用验证。",
      awaitingSync: "等待设备同步，请稍后刷新。", serviceReady: "设备已应用配置。请从外部网络验证访问。", servicePaused: "连接已暂停，启用后等待设备应用配置。",
      noAddressYet: "服务器尚未返回访问地址，请刷新重试。", NASDefaultName: "NAS", homeassistantDefaultName: "Home Assistant", immichDefaultName: "Immich", jellyfinDefaultName: "Jellyfin",
      serviceError: "配置未应用，请检查设备状态和目标服务。", wizardStepsLabel: "发布步骤"
    });
    Object.assign(strings.en, {
      wizardService: "Device and service", wizardTarget: "Local target", wizardAccess: "Public access", wizardPublish: "Review and publish",
      serviceTemplate: "Service template", typeHttps: "Web · Local HTTPS", checkTarget: "Check local target", ackTargetCheck: "I understand this result and will verify access after publishing.",
      publicWebHelp: "Public access uses the server's HTTPS domain. Choose the local HTTP/HTTPS scheme in the previous step.", reviewService: "Review service settings", publishHelp: "Wait for this device to apply the published configuration, then verify access from an external network.",
      connectionCreated: "Connection created", publish: "Publish service", nextStep: "Next", previousStep: "Back", targetNotChecked: "Check the local target before continuing.",
      TARGET_TCP_READY: "The local TCP port accepts connections. Application sign-in and public access still need verification.", TARGET_HTTP_READY: "The local Web service responded. Application sign-in and public access still need verification.",
      TARGET_HTTP_UNHEALTHY: "The local Web service returned a server error. Check the application or acknowledge this result to continue.", TARGET_UNREACHABLE: "The local port is unreachable. Start the service and check its address, port and firewall.",
      TARGET_HTTP_FAILED: "The local Web request failed. Check the scheme and service.", TARGET_TLS_FAILED: "The local HTTPS certificate or TLS handshake is invalid. Fix it and retry.",
      TARGET_INVALID: "Enter a valid host and port, without a URL, path or credentials.", UDP_MANUAL_CHECK: "Opening a UDP socket cannot prove reachability. After publishing, test with the target application from an external network.",
      awaitingSync: "Waiting for this device to apply the configuration. Refresh shortly.", serviceReady: "This device has applied the configuration. Verify access from an external network.", servicePaused: "This connection is paused. Enable it and wait for this device to apply the configuration.",
      noAddressYet: "The server has not returned an access address yet. Refresh to retry.", NASDefaultName: "NAS", homeassistantDefaultName: "Home Assistant", immichDefaultName: "Immich", jellyfinDefaultName: "Jellyfin",
      serviceError: "The configuration was not applied. Check the device and local service.", wizardStepsLabel: "Publishing steps"
    });
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
    $("nav-settings").append(updateDot);
    function setUpdateAvailable(result) {
      updateDot.hidden = !result.newer;
      $("nav-settings").setAttribute("aria-label", result.newer ? `${msg("软件更新：发现正式版 ")}${result.latest}` : t("settings"));
    }
    const remoteQuick = document.createElement("div");
    remoteQuick.className = "remote-quick";
    const remoteOverview = document.createElement("div");
    remoteOverview.className = "remote-overview";
    remoteOverview.innerHTML = '<article class="settings-card remote-intro-card remote-connect-card"><div class="remote-card-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12h16m-6-6 6 6-6 6"/></svg></div><h3>连接远程电脑</h3><p>输入对方的 9 位设备 ID，或选择在线设备。</p><form id="remote-connect-form" class="remote-manual"><label for="remote-device-id">设备 ID</label><div class="remote-manual-row"><input id="remote-device-id" type="text" autocomplete="off" spellcheck="false" placeholder="123 456 789" maxlength="40" required><button type="submit">开始连接</button></div></form><div id="remote-connect-list" class="remote-connect-list"></div><div class="remote-connect-actions"><button type="button" id="remote-open-assist" class="secondary">连接其他账号</button><button type="button" id="remote-open-console" class="secondary">打开网页远控</button></div></article>';
    remoteOverview.querySelector("#remote-open-console").insertAdjacentHTML("beforeend", actionIcon("external"));
    const hostCard = $("remote-host-card");
    hostCard.classList.add("remote-local-card");
    hostCard.querySelector("p.muted").textContent = "在本机批准单次授权后，绑定的会话自动启动；你可随时断开或撤销。";
    hostCard.insertAdjacentHTML("afterbegin", '<div class="remote-card-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/></svg></div>');
    hostCard.querySelector("h3").textContent = "允许对方连接这台电脑";
    hostCard.querySelector("p.muted").textContent = "把设备 ID 告诉对方。连接需要你在本机同意；设置固定密码后可无人值守连接。";
    const hostIdentity = document.createElement("div");
    hostIdentity.className = "remote-host-identity";
    hostIdentity.innerHTML = '<span>本机设备 ID</span><button type="button" id="rd-host-copy" class="secondary" disabled aria-label="复制本机设备 ID"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/></svg></button>';
    hostCard.querySelector("#rd-host-detail").before(hostIdentity);
    const hostCode = document.createElement("strong");
    hostCode.id = "rd-host-code";
    hostCode.className = "remote-host-code";
    hostCode.setAttribute("data-no-translate", "");
    hostIdentity.after(hostCode);
    const remoteAssistCard = document.createElement("article");
    remoteAssistCard.className = "settings-card remote-assist-card";
    remoteAssistCard.innerHTML = '<div class="remote-card-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a4 4 0 0 1 8 0v2M8 14h8"/></svg></div><h3>临时协助</h3><p>给其他账号提供一次性设备 ID 和临时密码。密码 5 分钟有效，使用一次即失效。</p><button type="button" id="rd-assist-create" disabled>生成临时密码</button><div id="rd-assist-secret" class="remote-assist-secret hidden"></div><div id="rd-assist-list"></div><p id="rd-assist-error" class="error" role="alert"></p>';
    const remoteSecurity = document.createElement("article");
    remoteSecurity.className = "settings-card remote-security-card";
    remoteSecurity.innerHTML = '<h3>连接请求与会话</h3>';
    for (const id of ["rd-host-pending", "rd-host-grants", "rd-host-files"]) remoteSecurity.append($(id));
    // Signing in already grants remote access. This short form only appears for
    // installs that signed in before the host could be registered automatically.
    const hostEnroll = $("rd-host-enroll");
    hostEnroll.classList.add("remote-host-enroll");
    hostCard.querySelector(".row").before(hostEnroll);
    hostCard.append($("rd-host-error"));
    remoteOverview.prepend(hostCard);
    remoteOverview.append(remoteAssistCard);
    remoteQuick.append(remoteOverview, remoteSecurity);
    const recentDevices = document.createElement("section");
    recentDevices.className = "recent-devices";
    recentDevices.innerHTML = '<div class="recent-devices-heading"><div><h2>最近设备</h2><p>从已登记设备快速进入</p></div><button type="button" id="remote-all-devices" class="secondary">查看所有设备</button></div><div id="recent-devices-list" class="recent-devices-list"></div>';
    recentDevices.querySelector("#remote-all-devices").insertAdjacentHTML("beforeend", actionIcon("arrow"));
    remoteQuick.append(recentDevices);
    // Unattended access is the fixed password: whoever knows the device ID and
    // this password connects without a local prompt. There is no separate mode.
    const remoteAccess = document.createElement("article");
    remoteAccess.className = "settings-card remote-access-card";
    remoteAccess.innerHTML = '<div class="remote-card-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 5v2"/></svg></div><div class="remote-fixed-password"><h3>固定密码（无人值守）</h3><p>设置后，对方输入设备 ID 和固定密码即可直接连接，无需你在本机同意。</p><p>仅限登录同一服务器的用户。修改或关闭固定密码会撤销旧授权。</p><p id="rd-fixed-scope" class="hidden">固定密码仅作用于已登录的桌面，不能控制锁屏、登录前或 UAC 安全桌面。</p><form id="rd-fixed-form"><label for="rd-fixed-password">新固定密码（至少 12 位）</label><div class="remote-manual-row"><input id="rd-fixed-password" type="password" autocomplete="new-password" minlength="12" maxlength="128" required><button type="submit" id="rd-fixed-save">保存密码</button></div></form><p id="rd-fixed-status" class="muted" role="status"></p><button type="button" id="rd-fixed-disable" class="danger" disabled>关闭固定密码</button></div><div id="rd-legacy-trust" class="remote-legacy-trust hidden"><p>这台电脑仍保留旧版长期授权。固定密码已可直接连接，建议关闭旧版授权。</p><button type="button" id="rd-legacy-disable" class="danger">关闭旧版长期授权</button></div><div class="remote-access-requests"><h3>待批准的连接请求</h3><div id="rd-access-requests"></div></div><div class="remote-hotkey-setting"><label for="rd-emergency-key">强制断开快捷键</label><select id="rd-emergency-key"><option value="X">Ctrl + Alt + Shift + X</option><option value="Q">Ctrl + Alt + Shift + Q</option><option value="F12">Ctrl + Alt + Shift + F12</option></select><p>按下后立即停止本机远控并关闭远控开关；重新启用需回到本页面。</p></div><p id="rd-access-error" class="error" role="alert"></p>';
    remoteQuick.insertBefore(remoteAccess, recentDevices);
    $("remote-page").append(remoteQuick);
    $("rd-host-copy").onclick = () => navigator.clipboard.writeText($("rd-host-code").textContent.replace(/\s/g, "")).catch(() => {});
    $("remote-all-devices").onclick = () => void showDevices();
    const updateLayout = document.createElement("div");
    updateLayout.className = "update-layout";
    const updateCard = $("settings-update").querySelector(".settings-card");
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
    const desktopMessages = {
      "\n临时密码：": ["\n临时密码：","\nOne-time password: "],
      "\n实例 / Instance: ": ["\n实例：","\nInstance: "],
      "\n密钥指纹 / Key: ": ["\n密钥指纹：","\nKey thumbprint: "],
      " 台设备": [" 台设备"," devices"],
      " 待批准 / pending": [" 待批准"," pending"],
      "Home Tunnel · 本机服务": ["Home Tunnel · 本机服务","Home Tunnel · Local services"],
      "MY DEVICES / 设备": ["设备","MY DEVICES"],
      "NETWORK TUNNELS / 内网穿透": ["内网穿透","NETWORK TUNNELS"],
      "REMOTE DESKTOP / 远程桌面": ["远程桌面","REMOTE DESKTOP"],
      "。请在控制端核对一致后确认。": ["。请在控制端核对一致后确认。",". Confirm the matching code on the controller."],
      "两次新密码不一致": ["两次新密码不一致","Passwords do not match"],
      "临时协助": ["临时协助","Temporary assistance"],
      "临时密码：": ["临时密码：","One-time password: "],
      "主导航": ["主导航","Main navigation"],
      "仅本次会话 / This session only": ["仅本次会话","This session only"],
      "仅本次显示，请安全地发送给对方": ["仅本次显示，请安全地发送给对方","Shown once. Share it securely with the other person."],
      "仅通过 UDP 直连。这台电脑每次只接受一个控制端；配对与会话均由你在本机批准。": ["仅通过 UDP 直连。这台电脑每次只接受一个控制端；配对与会话均由你在本机批准。","Direct UDP only. This computer accepts one controller at a time. Approve pairing and sessions on this device."],
      "从已登记设备快速进入": ["从已登记设备快速进入","Connect quickly to an enrolled device"],
      "从本机接收文件 / Receive files": ["从本机接收文件","Receive files"],
      "会话文件 / Session files": ["会话文件","Session files"],
      "传输中 / Transferring": ["传输中","Transferring"],
      "传输失败 / Failed": ["传输失败","Failed"],
      "保存密码": ["保存密码","Save password"],
      "保持应用最新": ["保持应用最新","Keep Home Tunnel up to date"],
      "允许以上权限 / Allow listed permissions": ["允许以上权限","Allow listed permissions"],
      "允许对方连接这台电脑": ["允许对方连接这台电脑","Allow access to this computer"],
      "允许远程连接": ["允许远程连接","Allow remote access"],
      "允许远程连接 / Enable": ["允许远程连接","Enable"],
      "允许连接这台电脑，或选择一台已登记的设备。": ["允许连接这台电脑，或选择一台已登记的设备。","Allow access to this computer or choose an enrolled device."],
      "公网地址": ["公网地址","Public address"],
      "关闭固定密码": ["关闭固定密码","Disable fixed password"],
      "关闭远程连接": ["关闭远程连接","Disable remote access"],
      "关闭远程连接 / Disable": ["关闭远程连接","Disable"],
      "内网穿透": ["内网穿透","Private tunnels"],
      "写入本机剪贴板 / Write local clipboard": ["写入本机剪贴板","Write local clipboard"],
      "切换主题": ["切换主题","Change theme"],
      "切换至浅色主题": ["切换至浅色主题","Switch to light theme"],
      "切换至深色主题": ["切换至深色主题","Switch to dark theme"],
      "刷新状态": ["刷新状态","Refresh status"],
      "刷新设备": ["刷新设备","Refresh devices"],
      "单次授权 · ": ["单次授权 · ","Session grant · "],
      "发现正式版后可下载并校验 SHA-256。安装前请退出正在进行的远控会话。": ["发现正式版后可下载并校验 SHA-256。安装前请退出正在进行的远控会话。","Download published updates with SHA-256 verification. End active remote sessions before installing."],
      "发送 / Send": ["发送","Send"],
      "发送文件到本机 / Send files here": ["发送文件到本机","Send files here"],
      "取消此文件 / Cancel file": ["取消此文件","Cancel file"],
      "只检查 GitHub 正式 Release，不显示未公开的测试包。": ["只检查 GitHub 正式 Release，不显示未公开的测试包。","Check published GitHub releases. Private test packages are excluded."],
      "同账号设备未找到或当前离线": ["同账号设备未找到或当前离线","This account's device was not found or is offline"],
      "固定密码已启用 · 可跨账号自动连接": ["固定密码已启用 · 可跨账号自动连接","Fixed password enabled · Other accounts can connect automatically"],
      "在本机批准单次授权后，绑定的会话自动启动；你可随时断开或撤销。": ["在本机批准单次授权后，绑定的会话自动启动；你可随时断开或撤销。","After local approval, the authorized session starts automatically. Disconnect or revoke access at any time."],
      "在线": ["在线","Online"],
      "复制协助信息": ["复制协助信息","Copy connection details"],
      "复制本机设备标识": ["复制本机设备标识","Copy this device ID"],
      "外观": ["外观","Appearance"],
      "密码 / Password": ["密码","Password"],
      "导出诊断包 / Export bundle": ["导出诊断包","Export bundle"],
      "正在生成…": ["正在生成…","Generating…"],
      "正在开启远程协助…": ["正在开启远程协助…","Turning on remote assistance…"],
      "本机设备 ID": ["本机设备 ID","This device ID"],
      "设备 ID": ["设备 ID","Device ID"],
      "连接请求与会话": ["连接请求与会话","Requests and sessions"],
      "开启远程协助": ["开启远程协助","Turn on remote assistance"],
      "请输入当前账号密码以开启远程协助。仅需一次。": ["请输入当前账号密码以开启远程协助。仅需一次。","Enter your account password once to turn on remote assistance."],
      "输入对方的 9 位设备 ID，或选择在线设备。": ["输入对方的 9 位设备 ID，或选择在线设备。","Enter the other computer's 9-digit device ID, or pick an online device."],
      "尚未登记": ["尚未登记","Not enrolled"],
      "屏幕 / Screen": ["屏幕","Screen"],
      "工作空间": ["工作空间","Workspace"],
      "已使用": ["已使用","Used"],
      "已保存": ["已保存","Saved"],
      "已允许连接": ["已允许连接","Remote access enabled"],
      "已取消 / Cancelled": ["已取消","Cancelled"],
      "已完成 / Complete": ["已完成","Complete"],
      "已读取最新版本。输入保持不变，请核对并重新保存。": ["已读取最新版本。输入保持不变，请核对并重新保存。","The latest version was loaded. Your input was preserved; review it before saving again."],
      "应用": ["应用","Application"],
      "开始连接": ["开始连接","Connect"],
      "强制断开快捷键": ["强制断开快捷键","Emergency disconnect shortcut"],
      "当前没有在线的其他设备": ["当前没有在线的其他设备","No other devices are online"],
      "当前没有更新的正式版本。": ["当前没有更新的正式版本。","You have the latest published version."],
      "当前版本": ["当前版本","Installed version"],
      "当前版本 ·": ["当前版本 ·","Installed version ·"],
      "当前连接使用的地址": ["当前连接使用的地址","Address used by this connection"],
      "待批准的连接请求": ["待批准的连接请求","Connection requests awaiting approval"],
      "我已核对服务器身份，信任此密钥 / Trust this server identity": ["我已核对服务器身份，信任此密钥","Trust this server identity"],
      "我的设备": ["我的设备","My devices"],
      "打开网页远控": ["打开网页远控","Open web remote control"],
      "批准本次连接": ["批准本次连接","Approve this connection"],
      "拒绝": ["拒绝","Reject"],
      "拒绝 / Reject": ["拒绝","Reject"],
      "按下后立即停止本机远控并关闭远控开关；重新启用需回到本页面。": ["按下后立即停止本机远控并关闭远控开关；重新启用需回到本页面。","Press the shortcut to disconnect and disable remote access immediately. Return here to enable it again."],
      "按名称或设备标识搜索": ["按名称或设备标识搜索","Search by device name or ID"],
      "授权与会话": ["授权与会话","Permissions and sessions"],
      "接收 / Receive": ["接收","Receive"],
      "搜索设备": ["搜索设备","Search devices"],
      "撤销": ["撤销","Revoke"],
      "撤销授权并断开 / Revoke and disconnect": ["撤销授权并断开","Revoke and disconnect"],
      "操作": ["操作","Actions"],
      "文件 / File": ["文件","File"],
      "文件可能已保存，请检查目标文件夹。 / The file may have been saved; check the destination folder.": ["文件可能已保存，请检查目标文件夹。","The file may have been saved; check the destination folder."],
      "文件通过当前直连传输。请先在控制端开启文件权限；本机选择文件或保存位置，不覆盖已有文件。 / Enable file transfer on the controller, then choose files or a new destination here.": ["文件通过当前直连传输。请先在控制端开启文件权限；本机选择文件或保存位置，不覆盖已有文件。","Enable file transfer on the controller, then choose files or a new destination here."],
      "文字输入 / Text input": ["文字输入","Text input"],
      "新固定密码（至少 12 位）": ["新固定密码（至少 12 位）","New fixed password (at least 12 characters)"],
      "无法读取远控状态 / Remote status unavailable": ["无法读取远控状态","Remote status unavailable"],
      "暂无请求": ["暂无请求","No requests"],
      "更新包未通过 SHA-256 校验 / Update verification failed": ["更新包未通过 SHA-256 校验","Update verification failed"],
      "更新由你决定。": ["更新由你决定。","You control updates."],
      "最近设备": ["最近设备","Recent devices"],
      "有效至 ": ["有效至 ","Expires "],
      "服务端公网端口已用完，请联系管理员扩容。": ["服务端公网端口已用完，请联系管理员扩容。","The server has no available public ports. Ask the administrator to expand the range."],
      "服务端密码与本机授权版本不一致，请重新设置": ["服务端密码与本机授权版本不一致，请重新设置","The server password and local authorization versions differ. Set the password again."],
      "未设置固定密码": ["未设置固定密码","No fixed password set"],
      "本地目标": ["本地目标","Local target"],
      "本机 · ": ["本机 · ","This device · "],
      "本机设备标识": ["本机设备标识","This device ID"],
      "查看同账号下已登记的电脑。": ["查看同账号下已登记的电脑。","View computers enrolled with your account."],
      "查看所有设备": ["查看所有设备","View all devices"],
      "查看服务器身份 / Verify server": ["查看服务器身份","Verify server"],
      "查看设备": ["查看设备","View device"],
      "核对码 / Compare code: ": ["核对码：","Compare code: "],
      "检查 DNS、HTTPS、FRPS 与本地服务。导出内容不含凭据、地址或原始日志。": ["检查 DNS、HTTPS、FRPS 与本地服务。导出内容不含凭据、地址或原始日志。","Check DNS, HTTPS, FRPS and local services. Exported reports exclude credentials, addresses and raw logs."],
      "检查更新": ["检查更新","Check for updates"],
      "检查正式版本": ["检查正式版本","Check published releases"],
      "正在检查…": ["正在检查…","Checking…"],
      "正在检查本机能力…": ["正在检查本机能力…","Checking this device's capabilities…"],
      "此安装包没有可用的远控后端": ["此安装包没有可用的远控后端","This package has no available remote control backend"],
      "没有匹配的设备": ["没有匹配的设备","No matching devices"],
      "浅色": ["浅色","Light"],
      "深色": ["深色","Dark"],
      "版本与安装": ["版本与安装","Version and installation"],
      "状态": ["状态","Status"],
      "生成临时密码": ["生成临时密码","Generate one-time password"],
      "由本机处理会话授权，你可以随时断开。": ["由本机处理会话授权，你可以随时断开。","Approve access on this computer and disconnect at any time."],
      "登记本机 / Enroll": ["登记本机","Enroll"],
      "离线": ["离线","Offline"],
      "私有候选版本不会显示为公开更新。": ["私有候选版本不会显示为公开更新。","Private candidate builds are excluded from public updates."],
      "立即断开": ["立即断开","Disconnect now"],
      "立即断开 / Disconnect": ["立即断开","Disconnect"],
      "等待连接": ["等待连接","Waiting for a connection"],
      "等待选择 / Awaiting selection": ["等待选择","Awaiting selection"],
      "粘贴设备标识": ["粘贴设备标识","Paste device ID"],
      "系统声音 / System audio": ["系统声音","System audio"],
      "给其他账号提供一次性设备 ID 和临时密码。密码 5 分钟有效，使用一次即失效。": ["给其他账号提供一次性设备 ID 和临时密码。密码 5 分钟有效，使用一次即失效。","Share this device ID and a one-time password with another account. The password expires after 5 minutes or one use."],
      "网页控制台": ["网页控制台","Web console"],
      "网页远控当前不可用": ["网页远控当前不可用","Web remote control is unavailable"],
      "设备 ID：": ["设备 ID：","Device ID: "],
      "设备列表暂不可用": ["设备列表暂不可用","The device list is temporarily unavailable"],
      "设备标识": ["设备标识","Device ID"],
      "设置": ["设置","Settings"],
      "诊断 / Diagnostics": ["诊断","Diagnostics"],
      "读取本机剪贴板 / Read local clipboard": ["读取本机剪贴板","Read local clipboard"],
      "账号 / Account": ["账号","Account"],
      "跟随系统": ["跟随系统","Follow system"],
      "软件更新": ["软件更新","Software updates"],
      "软件更新：发现正式版 ": ["软件更新：发现正式版 ","Software updates: release available "],
      "输入同账号设备标识，或选择在线设备。": ["输入同账号设备标识，或选择在线设备。","Enter a device ID from your account or choose an online device."],
      "运行诊断 / Run checks": ["运行诊断","Run checks"],
      "还没有其他已登记设备": ["还没有其他已登记设备","No other enrolled devices yet"],
      "还没有登记设备": ["还没有登记设备","No enrolled devices yet"],
      "远程会话请求 / Session request": ["远程会话请求","Session request"],
      "远程会话进行中": ["远程会话进行中","Remote session active"],
      "远程协助 / Remote assistance": ["远程协助","Remote assistance"],
      "远程协助，直接开始。": ["远程协助，直接开始。","Start a remote connection."],
      "远程控制": ["远程控制","Remote control"],
      "远程桌面": ["远程桌面","Remote desktop"],
      "远程连接已关闭": ["远程连接已关闭","Remote access disabled"],
      "连接其他账号": ["连接其他账号","Connect to another account"],
      "连接名称": ["连接名称","Connection name"],
      "连接远程电脑": ["连接远程电脑","Connect to another computer"],
      "选择保存位置 / Choose destination": ["选择保存位置","Choose destination"],
      "选择多个文件发送 / Select files to send": ["选择多个文件发送","Select files to send"],
      "配对请求 / Pairing request": ["配对请求","Pairing request"],
      "键盘 / Keyboard": ["键盘","Keyboard"],
      "首次启用需核对服务器身份；进行中的会话可在这里立即撤销。": ["首次启用需核对服务器身份；进行中的会话可在这里立即撤销。","Verify the server identity before first use. Revoke active sessions here at any time."],
      "首次启用需要本设备所属账号验证。密码仅用于本次登记。": ["首次启用需要本设备所属账号验证。密码仅用于本次登记。","Verify the account that owns this device before first use. The password is used only for this enrollment."],
      "首次登录请设置新密码后继续。": ["首次登录请设置新密码后继续。","Set a new password before continuing."],
      "麦克风回传 / Microphone": ["麦克风回传","Microphone"],
      "鼠标 / Pointer": ["鼠标","Pointer"],
      "把设备 ID 告诉对方。连接需要你在本机同意；设置固定密码后可无人值守连接。": ["把设备 ID 告诉对方。连接需要你在本机同意；设置固定密码后可无人值守连接。","Share this device ID. Connections need your approval here; set a fixed password for unattended access."],
      "固定密码（无人值守）": ["固定密码（无人值守）","Fixed password (unattended access)"],
      "设置后，对方输入设备 ID 和固定密码即可直接连接，无需你在本机同意。": ["设置后，对方输入设备 ID 和固定密码即可直接连接，无需你在本机同意。","Once set, anyone with the device ID and fixed password connects directly, without your approval on this computer."],
      "仅限登录同一服务器的用户。修改或关闭固定密码会撤销旧授权。": ["仅限登录同一服务器的用户。修改或关闭固定密码会撤销旧授权。","Only users signed in to the same server can connect. Changing or disabling the fixed password revokes previous access."],
      "固定密码仅作用于已登录的桌面，不能控制锁屏、登录前或 UAC 安全桌面。": ["固定密码仅作用于已登录的桌面，不能控制锁屏、登录前或 UAC 安全桌面。","The fixed password works on a signed-in desktop only. It cannot control the lock screen, sign-in, or UAC secure desktop."],
      "这台电脑仍保留旧版长期授权。固定密码已可直接连接，建议关闭旧版授权。": ["这台电脑仍保留旧版长期授权。固定密码已可直接连接，建议关闭旧版授权。","This computer still has legacy long-term access. The fixed password now covers direct connections, so turn legacy access off."],
      "关闭旧版长期授权": ["关闭旧版长期授权","Turn off legacy long-term access"],
      "旧版长期授权 · ": ["旧版长期授权 · ","Legacy long-term access · "],
      "本机不再提供长期授权，请让对方改用固定密码连接。": ["本机不再提供长期授权，请让对方改用固定密码连接。","Long-term access is no longer offered. Ask the other person to connect with the fixed password."],
      "控制台地址无效": ["控制台地址无效","Invalid console address"],
      "无法打开默认浏览器": ["无法打开默认浏览器","Cannot open the default browser"],
      "请先登录": ["请先登录","Sign in first"],
      "<div class=\"service-list-head\"><span>连接名称</span><span>公网地址</span><span>本地目标</span><span>状态</span><span>操作</span></div>": ["<div class=\"service-list-head\"><span>连接名称</span><span>公网地址</span><span>本地目标</span><span>状态</span><span>操作</span></div>","<div class=\"service-list-head\"><span>Connection name</span><span>Public address</span><span>Local target</span><span>Status</span><span>Actions</span></div>"],
    };
    let locale = document.documentElement.lang === "en" ? "en" : "zh-CN";
    const msg = key => desktopMessages[key]?.[locale === "en" ? 1 : 0] ?? key;
    // Capture only the initial product nodes. Later device names, file names,
    // credentials and API data are never searched or rewritten by this binding.
    const staticLocaleBindings = [];
    const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT);
    let productNode;
    while ((productNode = walker.nextNode())) {
      if (productNode.parentElement.closest("script,style,[data-i18n],[data-no-translate]")) continue;
      const original = productNode.nodeValue, key = original.trim();
      if (Object.hasOwn(desktopMessages, key)) staticLocaleBindings.push({ node: productNode, original, key });
    }
    for (const element of document.querySelectorAll("[aria-label],[title],[placeholder]")) {
      for (const attribute of ["aria-label", "title", "placeholder"]) {
        const key = element.getAttribute(attribute);
        if (Object.hasOwn(desktopMessages, key)) staticLocaleBindings.push({ node: element, attribute, key });
      }
    }
    const themeMedia = window.matchMedia("(prefers-color-scheme: dark)");
    const t = (key) => (strings[locale] && strings[locale][key]) || strings["zh-CN"][key] || key;
    function applyLocale() {
      document.documentElement.lang = locale;
      for (const binding of staticLocaleBindings) {
        if (!binding.node.isConnected) continue;
        if (binding.attribute) binding.node.setAttribute(binding.attribute, msg(binding.key));
        else binding.node.nodeValue = binding.original.replace(binding.key, msg(binding.key));
      }
      document.querySelectorAll("[data-i18n]").forEach((node) => { node.textContent = t(node.dataset.i18n); });
      for (const [id, icon] of [["add", "plus"], ["refresh", "refresh"]]) $(id).insertAdjacentHTML("afterbegin", actionIcon(icon));
      $("service-search").placeholder = t("searchServices");
      for (const id of ["locale-toggle", "sidebar-locale"]) $(id).textContent = locale === "en" ? "中" : "EN";
      try { localStorage.setItem("ht_locale", locale); } catch (e) {}
    }
    function applyTheme(preference) {
      if (!["light", "dark", "system"].includes(preference)) preference = "system";
      const theme = preference === "system" ? themeMedia.matches ? "dark" : "light" : preference;
      document.documentElement.dataset.themePreference = preference;
      document.documentElement.dataset.theme = theme;
      document.documentElement.style.colorScheme = theme;
      const icon = theme === "dark"
        ? '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
        : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20.5 14.2A8.5 8.5 0 0 1 9.8 3.5 8.5 8.5 0 1 0 20.5 14.2Z"/></svg>';
      for (const id of ["theme-toggle", "sidebar-theme"]) {
        $(id).innerHTML = icon;
        $(id).setAttribute("aria-label", theme === "dark" ? msg("切换至浅色主题") : msg("切换至深色主题"));
      }
      try { localStorage.setItem("ht_theme", preference); } catch (e) {}
    }
    applyLocale();
    applyTheme(document.documentElement.dataset.themePreference || "system");
    themeMedia.addEventListener("change", () => {
      if (document.documentElement.dataset.themePreference === "system") applyTheme("system");
    });
    $("locale-toggle").onclick = () => {
      locale = locale === "en" ? "zh-CN" : "en";
      applyLocale(); applyTheme(document.documentElement.dataset.themePreference); renderServices(); renderAccountDevices();
      void refreshRemoteHost();
      if (!$("settings").classList.contains("hidden")) void checkUpdates();
      if (!$("editor").classList.contains("hidden")) { applyProtocol(); if (wizardActive) renderWizard(false); }
    };
    $("theme-toggle").onclick = () => applyTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark");
    $("server").value = localStorage.getItem("ht_server") || "";
    $("username").value = localStorage.getItem("ht_username") || "";
    const localSessionToken = new URLSearchParams(location.hash.slice(1)).get("session") || "";
    async function api(path, options = {}) {
      const response = await fetch(path, { ...options, headers: { "content-type": "application/json", ...(options.headers || {}), ...(localSessionToken ? { authorization: `Bearer ${localSessionToken}` } : {}) } });
      const text = await response.text();
      const data = text ? JSON.parse(text) : null;
      if (!response.ok) {
        const descriptions = { RD_SELF_CONNECTION: t("selfConnection"), CLIENT_RAW_TUNNELS_DISABLED: t("rawNotAllowed"), TCP_TUNNELS_DISABLED: t("transportDisabled"), UDP_TUNNELS_DISABLED: t("transportDisabled"), PORT_POOL_EXHAUSTED: locale === "en" ? "The server has no available public ports. Ask the administrator to expand the range." : msg("服务端公网端口已用完，请联系管理员扩容。"), VERSION_CONFLICT: t("conflict") };
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
    let localDeviceID = "", localAccessID = "", devicesRevision = 0;
    let renameSaving = false, renameRevision = 0;
    function closeRename() { ++renameRevision; $("device-rename").close(); $("device-name").value = ""; $("device-rename-error").textContent = ""; }
    function openRename(device) {
      if (renameSaving || device.id !== localDeviceID) return;
      ++renameRevision;
      $("device-name").value = device.name || "";
      $("device-rename-error").textContent = "";
      $("device-rename").showModal();
      $("device-name").focus(); $("device-name").select();
    }
    $("device-rename-cancel").onclick = closeRename;
    $("device-rename").addEventListener("cancel", event => { event.preventDefault(); closeRename(); });
    $("device-rename-form").onsubmit = async event => {
      event.preventDefault();
      if (renameSaving || !$("device-rename-form").reportValidity()) return;
      const name = $("device-name").value.trim(), revision = renameRevision, generation = remoteHostGeneration;
      if (!name) { $("device-rename-error").textContent = locale === "en" ? "Enter a device name." : "请输入设备名称。"; return; }
      renameSaving = true; $("device-rename-save").disabled = true;
      $("device-rename-cancel").textContent = t("close");
      $("device-rename-pending").textContent = t("renamePending");
      $("device-rename-error").textContent = "";
      try {
        const result = await api("/local/device/name", {method: "PATCH", body: JSON.stringify({name})});
        if (generation !== remoteHostGeneration) return;
        const savedName = result.device_name;
        ++devicesRevision;
        accountDevices = accountDevices.map(device => device.id === localDeviceID ? {...device, name: savedName} : device);
        $("machine-name").textContent = $("sidebar-machine").textContent = savedName;
        renderAccountDevices();
        $("devices-notice").textContent = t("deviceRenamed");
        if (revision === renameRevision) closeRename();
      } catch (error) { if (revision === renameRevision) $("device-rename-error").textContent = error.message; }
      finally { renameSaving = false; $("device-rename-save").disabled = false; $("device-rename-cancel").textContent = t("cancel"); $("device-rename-pending").textContent = ""; }
    };
    async function openDeviceRemote(device) {
      if (!consoleUrl || !device?.id) return;
      const error = $("remote-page").classList.contains("hidden") ? $("devices-error") : $("remote-open-error");
      error.textContent = "";
      if (device.id === localDeviceID) { error.textContent = t("selfConnection"); return; }
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
      name.setAttribute("data-no-translate", "");
      name.textContent = device.name || t("unnamedComputer");
      const status = document.createElement("small");
      const online = device.status === "active" && device.online;
      status.textContent = `${device.id === localDeviceID ? msg("本机 · ") : ""}${online ? msg("在线") : msg("离线")} · ${device.id || "—"}`;
      details.append(name, status);
      const action = document.createElement("button");
      action.type = "button";
      action.className = "secondary";
      const local = device.id === localDeviceID;
      action.textContent = local ? t("renameDevice") : compact ? msg("查看设备") : msg("远程控制");
      if (!local) action.insertAdjacentHTML("beforeend", actionIcon(compact ? "arrow" : "external"));
      action.disabled = !local && !compact && (!online || !consoleUrl);
      action.onclick = local ? () => openRename(device) : compact ? () => void showDevices() : () => void openDeviceRemote(device);
      card.append(icon, details, action);
      return card;
    }
    function renderAccountDevices() {
      const filtered = accountDevices.filter((device) => `${device.name || ""} ${device.id || ""}`.toLocaleLowerCase().includes($("devices-search").value.trim().toLocaleLowerCase()));
      $("devices-count").textContent = `${filtered.length}${msg(" 台设备")}`;
      $("devices-list").replaceChildren(...filtered.map((device) => createDeviceCard(device)));
      if (!filtered.length) $("devices-list").textContent = accountDevices.length ? msg("没有匹配的设备") : msg("还没有登记设备");
      const recent = accountDevices.filter((device) => device.id !== localDeviceID).slice(0, 3);
      $("recent-devices-list").replaceChildren(...recent.map((device) => createDeviceCard(device, true)));
      if (!recent.length) $("recent-devices-list").textContent = msg("还没有其他已登记设备");
      const connect = accountDevices.filter((device) => device.id !== localDeviceID && device.status === "active" && device.online).slice(0, 2);
      $("remote-connect-list").replaceChildren(...connect.map((device) => {
        const row = document.createElement("button");
        row.type = "button";
        row.className = "secondary remote-connect-device";
        row.disabled = !consoleUrl;
        const name = document.createElement("strong");
        name.setAttribute("data-no-translate", "");
        name.textContent = device.name || t("unnamedComputer");
        const hint = document.createElement("span");
        hint.textContent = msg("远程控制");
        hint.insertAdjacentHTML("beforeend", actionIcon("external"));
        row.append(name, hint);
        row.onclick = () => void openDeviceRemote(device);
        return row;
      }));
      if (!connect.length) $("remote-connect-list").textContent = msg("当前没有在线的其他设备");
    }
    async function loadDevices() {
      const revision = ++devicesRevision;
      const result = await api("/local/devices");
      if (revision !== devicesRevision) return;
      accountDevices = (result.items || []).sort((left, right) => Number(right.online) - Number(left.online));
      localDeviceID = result.local_device_id || "";
      renderAccountDevices();
    }
    $("rd-host-enable").textContent = msg("允许远程连接");
    $("rd-host-disable").textContent = msg("关闭远程连接");
    $("rd-host-stop").textContent = msg("立即断开");
    $("remote-connect-form").onsubmit = (event) => {
      event.preventDefault();
      $("remote-open-error").textContent = "";
      // A 9-digit device ID reaches any account's host; spaces and dashes are grouping only.
      const code = $("remote-device-id").value.replace(/[\s-]/g, "");
      if (code === localAccessID || $("remote-device-id").value.trim().toLowerCase() === localDeviceID.toLowerCase() && localDeviceID) {
        $("remote-open-error").textContent = t("selfConnection"); return;
      }
      if (/^[0-9]{9}$/.test(code)) {
        api("/local/remote/window", {method:"POST", body:JSON.stringify({assist:true, access_id:code})}).catch(error => { $("remote-open-error").textContent = error.message; });
        return;
      }
      const id = $("remote-device-id").value.trim().toLowerCase();
      const device = accountDevices.find((item) => item.id?.toLowerCase() === id);
      if (!device || device.id === localDeviceID || device.status !== "active" || !device.online) {
        $("remote-open-error").textContent = msg("同账号设备未找到或当前离线");
        return;
      }
      if (!consoleUrl) {
        $("remote-open-error").textContent = msg("网页远控当前不可用");
        return;
      }
      void openDeviceRemote(device);
    };
    // The web console opens in the default browser. Go derives the address from
    // the signed-in server, so the page cannot ask it to open another URL.
    async function openConsole(section, errorId) {
      $(errorId).textContent = "";
      try { await api("/local/console/open", { method: "POST", body: JSON.stringify(section ? { section } : {}) }); }
      catch (error) { $(errorId).textContent = msg(error.message); }
    }
    $("remote-open-console").onclick = () => { if (consoleUrl) void openConsole("remote", "remote-open-error"); };
    $("remote-open-assist").onclick = async () => {
      $("remote-open-error").textContent = "";
      try { await api("/local/remote/window", {method:"POST", body:JSON.stringify({assist:true})}); }
      catch (error) { $("remote-open-error").textContent = error.message; }
    };
    function selectNavigation(name) {
      document.body.classList.add("workspace-active");
      $("app-sidebar").classList.remove("hidden");
      for (const item of ["remote", "devices", "tunnels", "settings"])
        $("nav-" + item).classList.toggle("active", item === name);
    }
    function hideWorkspacePages() {
      if ($("device-rename").open) closeRename();
      for (const item of ["login", "home", "settings", "editor", "remote-page", "devices-page"])
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
      void loadDevices().catch(() => { $("recent-devices-list").textContent = msg("设备列表暂不可用"); });
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
    async function showSettings() {
      const revision = ++navigationRevision;
      hideWorkspacePages(); $("settings").classList.remove("hidden"); selectNavigation("settings");
      $("settings-error").textContent = "";
      $("settings-server").textContent = consoleUrl || t("working");
      const state = await api("/local/state");
      if (revision !== navigationRevision) return;
      if (!state.enrolled) { await showRemote(); return; }
      consoleUrl = state.console_url || "";
      $("settings-server").textContent = consoleUrl || "—";
      $("sidebar-machine").textContent = state.device_name || t("unnamedComputer");
      $("update-current-version").textContent = $("update-version-badge").textContent = state.version || "—";
      void checkUpdates();
    }
    let checkingUpdates = false;
    async function checkUpdates() {
      if (checkingUpdates) return;
      checkingUpdates = true; $("update-check").disabled = true;
      const status = $("update-page-status");
      status.textContent = locale === "en" ? "Checking…" : msg("正在检查…");
      try {
        const result = await api("/local/update");
        setUpdateAvailable(result);
        $("update-current-version").textContent = result.current || "—";
        $("update-version-badge").textContent = result.current || "—";
        status.replaceChildren();
        status.append(result.newer ? `${t("updatePrefix")}${result.latest}${t("updateCurrent")}${result.current}${t("updateSuffix")}` : (locale === "en" ? "No newer stable release." : msg("当前没有更新的正式版本。")));
        if (result.newer && result.download_url) {
          const download = document.createElement("button");
          download.type = "button";
          download.textContent = t("download");
          download.onclick = async () => {
            download.disabled = true;
            try {
              const packageResult = await api("/local/update/download", { method: "POST" });
              if (packageResult.verified !== true) throw new Error(msg("更新包未通过 SHA-256 校验 / Update verification failed"));
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
      finally { checkingUpdates = false; $("update-check").disabled = false; }
    }
    let capabilities = {};
    let serverStale = false;
    const protocols = {
      http: { transport: "http", port: 8080 }, tcp: { transport: "tcp", port: 8080 },
      https: { transport: "http", port: 443, scheme: "https" }, nas: { transport: "http", port: 5000, name: "NASDefaultName" },
      homeassistant: { transport: "http", port: 8123, name: "homeassistantDefaultName" }, immich: { transport: "http", port: 2283, name: "immichDefaultName" },
      jellyfin: { transport: "http", port: 8096, name: "jellyfinDefaultName" },
      udp: { transport: "udp", port: 51820 }, rtsp: { transport: "tcp", port: 554, app: "rtsp" },
      ssh: { transport: "tcp", port: 22, app: "ssh" }, rdp: { transport: "tcp", port: 3389, app: "rdp" }
    };
    let wizardActive = false, wizardStep = 0, targetCheck = null, targetRevision = 0, targetAbort = null, createdConnection = null, suggestedName = "";
    const wizardPanels = ["wizard-service", "wizard-target", "wizard-access", "wizard-review"];
    function targetPayload() {
      return { proxy_type: protocols[$("protocol").value].transport, local_host: $("host").value.trim(), local_port: Number($("port").value), local_scheme: $("scheme").value };
    }
    function invalidateTarget() {
      targetRevision++; targetAbort?.abort(); targetAbort = null; targetCheck = null;
      $("target-result").textContent = ""; $("target-result").removeAttribute("data-status");
      $("target-ack").checked = false; $("target-ack-row").classList.add("hidden");
      if (wizardActive) renderWizard(false);
    }
    function targetMayProceed() {
      return targetCheck && (targetCheck.status === "pass" || ["manual", "warning"].includes(targetCheck.status) && $("target-ack").checked);
    }
    function validateWizardPanel(index) {
      const invalid = [...$(wizardPanels[index]).querySelectorAll("input,select")].find(field => !field.disabled && !field.checkValidity());
      if (!invalid) return true;
      wizardStep = index; renderWizard(false); invalid.reportValidity(); invalid.focus(); return false;
    }
    function renderWizard(focus = true) {
      $("wizard-steps").classList.toggle("hidden", !wizardActive);
      $("wizard-steps").setAttribute("aria-label", t("wizardStepsLabel"));
      $("editor-fields").classList.toggle("wizard-active", wizardActive);
      $("wizard-device").classList.toggle("hidden", !wizardActive);
      $("wizard-device").textContent = t("thisComputer") + " · " + ($("machine-name").textContent || t("unnamedComputer"));
      $("wizard-probe").classList.toggle("hidden", !wizardActive);
      wizardPanels.forEach((id, index) => $(id).classList.toggle("hidden", wizardActive ? index !== wizardStep : index === 3));
      [...$("wizard-steps").children].forEach((node, index) => { if (index === wizardStep) node.setAttribute("aria-current", "step"); else node.removeAttribute("aria-current"); });
      $("wizard-back").classList.toggle("hidden", !wizardActive || wizardStep === 0 || Boolean(createdConnection));
      $("wizard-next").classList.toggle("hidden", !wizardActive || wizardStep === 3);
      $("wizard-next").disabled = Boolean(creationBlock(protocols[$("protocol").value])) || wizardStep === 1 && !targetMayProceed();
      $("save").classList.toggle("hidden", wizardActive && (wizardStep !== 3 || Boolean(createdConnection)));
      $("save").textContent = t(wizardActive ? "publish" : "save");
      $("cancel").textContent = t(createdConnection ? "backServices" : "cancel");
      $("wizard-result").classList.toggle("hidden", !createdConnection);
      if (targetCheck) $("target-result").textContent = t(targetCheck.code);
      if (wizardActive && wizardStep === 3) {
        const target = targetPayload();
        const rows = [[t("name"), $("name").value], [t("serviceTemplate"), $("protocol").selectedOptions[0].textContent],
          [t("host"), target.local_host], [t("port"), String(target.local_port)], [t("scheme"), target.proxy_type === "http" ? target.local_scheme.toUpperCase() : target.proxy_type.toUpperCase()],
          [t("wizardAccess"), target.proxy_type === "http" ? $("subdomain").value : t("rawPortNote")]];
        $("wizard-summary").replaceChildren(...rows.flatMap(([label, value]) => { const term = document.createElement("dt"), detail = document.createElement("dd"); term.textContent = label; detail.textContent = value; return [term, detail]; }));
        if (createdConnection) renderCreatedConnection();
      }
      if (focus && wizardActive) {
        const destination = wizardStep === 3 ? $("save") : $(wizardPanels[wizardStep]).querySelector("input:not([disabled]),select:not([disabled]),button:not([disabled])");
        destination?.focus();
      }
    }
    async function checkWizardTarget() {
      if (!validateWizardPanel(1)) return;
      invalidateTarget(); const revision = targetRevision, signature = JSON.stringify(targetPayload());
      targetAbort = new AbortController(); const signal = targetAbort.signal;
      await runAction($("target-check"), async () => {
        let result;
        try { result = await api("/local/connection-check", { method: "POST", body: signature, signal }); }
        catch (error) { if (revision !== targetRevision || signal.aborted) return; throw error; }
        if (revision !== targetRevision || signature !== JSON.stringify(targetPayload()) || !wizardActive) return;
        if (!["pass", "fail", "warning", "manual"].includes(result.status) || !Object.hasOwn(strings.en, result.code)) throw new Error(t("failed"));
        targetCheck = result; $("target-result").textContent = t(result.code); $("target-result").dataset.status = result.status;
        $("target-ack-row").classList.toggle("hidden", !["manual", "warning"].includes(result.status)); renderWizard(false);
      }, "target-result");
    }
    function nextWizardStep() {
      if (!validateWizardPanel(wizardStep) || creationBlock(protocols[$("protocol").value])) return;
      if (wizardStep === 1 && !targetMayProceed()) { $("target-result").textContent = t("targetNotChecked"); return; }
      if (wizardStep < 3) { wizardStep++; renderWizard(); }
    }
    function renderCreatedConnection() {
      const item = createdConnection, address = item.access_url || item.public_url || item.public_endpoint || "";
      $("wizard-address").value = address; $("wizard-copy").disabled = !address;
      const applied = item.state === "Online" && Number(item.applied_version) >= Number(item.version) && Number(item.version) > 0;
      $("wizard-result-state").textContent = t(item.enabled === false ? "servicePaused" : item.last_error_code ? "serviceError" : applied ? "serviceReady" : "awaitingSync") + (address ? "" : " " + t("noAddressYet"));
    }
    $("target-check").onclick = () => void checkWizardTarget();
    $("target-ack").onchange = () => renderWizard(false);
    for (const id of ["host", "port", "scheme"]) $(id).addEventListener("input", invalidateTarget);
    $("wizard-next").onclick = nextWizardStep;
    $("wizard-back").onclick = () => { if (wizardStep > 0 && !createdConnection) { wizardStep--; renderWizard(); } };
    $("wizard-copy").onclick = () => runAction($("wizard-copy"), async () => { await navigator.clipboard.writeText($("wizard-address").value); $("wizard-result-state").textContent = t("copied"); }, "edit-error");
    $("wizard-refresh").onclick = () => runAction($("wizard-refresh"), async () => {
      const id = createdConnection?.id, result = await api("/local/connections");
      if (!id || createdConnection?.id !== id || !wizardActive) return;
      const item = result.items?.find(connection => connection.id === id);
      if (item) createdConnection = item;
      renderCreatedConnection();
    }, "edit-error");
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
        $("scheme").value = preset.scheme || "http";
        if (!$("name").value || $("name").value === suggestedName) { suggestedName = preset.name ? t(preset.name) : preset.app ? t(preset.app + "DefaultName") : ""; $("name").value = suggestedName; }
        invalidateTarget();
      }
      const blocked = creationBlock(preset);
      const details = [blocked || (raw ? t("rawPortNote") : "")];
      if (kind === "rtsp") details.push(t("rtspNote"));
      if (kind === "udp") details.push(t("udpNote"));
      if (raw && editBaseline?.public_endpoint) details.push(t("assignedAddress") + (editBaseline.access_url || editBaseline.public_endpoint));
      $("transport-note").textContent = details.filter(Boolean).join("\n");
      $("transport-note").classList.toggle("unavailable", Boolean(blocked));
      $("save").disabled = Boolean(blocked);
      $("wizard-raw-access").classList.toggle("hidden", !raw);
      if (wizardActive) renderWizard(false);
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
      wizardActive = true; wizardStep = 0; createdConnection = null; suggestedName = ""; invalidateTarget();
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
      renderWizard(false);
    }
    function fillEditor(item) {
      wizardActive = false; createdConnection = null; invalidateTarget();
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
      renderWizard(false);
    }
    async function quitApp() {
      if (!confirm(t("confirmQuit"))) return;
	  resetRemoteHostUI();
      await api("/local/quit", { method: "POST" });
      document.body.innerHTML = "<main><p class='muted'>" + escapeHtml(t("quitApp")) + "</p></main>";
    }
    async function showHome(background = false) {
      if (!background && $("device-rename").open) closeRename();
      if (refreshing || background && (!$("editor").classList.contains("hidden") || !$("login").classList.contains("hidden") || !$("settings").classList.contains("hidden") || !$("remote-page").classList.contains("hidden") || !$("devices-page").classList.contains("hidden"))) return;
      const revision = background ? navigationRevision : ++navigationRevision;
      refreshing = true;
      try {
      $("settings").classList.add("hidden");
      $("login").classList.add("hidden");
      $("editor").classList.add("hidden");
      $("remote-page").classList.add("hidden");
      $("devices-page").classList.add("hidden");
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
                if (result.verified !== true) throw new Error(msg("更新包未通过 SHA-256 校验 / Update verification failed"));
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
    function renderServices() {
      for (const id of selectedConnections) if (!connections.some(item => item.id === id)) selectedConnections.delete(id);
      $("batch-pause").disabled = $("batch-resume").disabled = selectedConnections.size === 0;
      $("batch-count").textContent = `${selectedConnections.size} / 50`;
      const search = $("service-search").value.trim().toLowerCase();
      const filter = $("service-filter").value;
      const items = connections.filter(item => (!search || `${item.name} ${item.subdomain} ${item.local_host}`.toLowerCase().includes(search)) && (filter === "all" || filter === "paused" && !item.enabled || filter === "online" && item.enabled && item.state === "Online"));
      $("connections").innerHTML = items.length ? msg("<div class=\"service-list-head\"><span>连接名称</span><span>公网地址</span><span>本地目标</span><span>状态</span><span>操作</span></div>") + items.map(item => {
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
    $("settings-open").onclick = () => runAction($("settings-open"), showSettings, "settings-error");
    for (const enabled of [false, true]) {
      const button = $(enabled ? "batch-resume" : "batch-pause");
      button.onclick = () => runAction(button, async () => {
        const items = connections.filter(item => selectedConnections.has(item.id));
        if (!items.length || items.length > 50) return;
        const verb = t(enabled ? "batchResume" : "batchPause");
        if (!confirm(`${verb} (${items.length})?\n${items.map(item => item.name).join("\n")}`)) return;
        const result = await api("/local/batch", {method: "POST", body: JSON.stringify({enabled, items: items.map(item => ({id:item.id,expected_version:item.version}))})});
        $("batch-results").textContent = result.results.map(row => `${items.find(item => item.id === row.id)?.name || row.id}: ${row.status === 200 ? (locale === "en" ? "Saved" : msg("已保存")) : row.error_code || row.status}`).join("\n");
        selectedConnections.clear(); await showHome();
      });
    }
    $("login-form").onsubmit = async (event) => {
      event.preventDefault();
      if (!$("login-form").reportValidity()) return;
      if (!$("password-change").classList.contains("hidden") && $("new-password").value !== $("confirm-password").value) { $("login-error").textContent = locale === "en" ? "Passwords do not match" : msg("两次新密码不一致"); return; }
      await runAction($("login-button"), async () => {
	  resetRemoteHostUI();
      $("login-error").textContent = "";
      try {
        localStorage.setItem("ht_server", $("server").value);
        localStorage.setItem("ht_username", $("username").value);
        await api("/local/login", { method: "POST", body: JSON.stringify({ server: $("server").value, username: $("username").value, password: $("password").value, new_password: $("new-password").value }) });
        $("password").value = $("new-password").value = $("confirm-password").value = "";
        await showRemote();
      } catch (error) {
        if (/requires a password change|PASSWORD_CHANGE_REQUIRED/.test(error.message)) {
          $("password-change").classList.remove("hidden"); $("new-password").required = true; $("confirm-password").required = true; $("new-password").focus();
          $("login-error").textContent = locale === "en" ? "Set a new password to continue." : msg("首次登录请设置新密码后继续。");
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
    $("console").onclick = () => { if (consoleUrl) void openConsole("", "status"); };
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
    $("add").onclick = () => { ++navigationRevision; resetEditor(); $("home").classList.add("hidden"); $("editor").classList.remove("hidden"); selectNavigation("tunnels"); renderWizard(); };
    $("cancel").onclick = () => runAction($("cancel"), () => showHome());
    let availabilityRequest = 0, availabilityTimer;
    $("subdomain").addEventListener("input", () => {
      if (protocols[$("protocol").value]?.transport !== "http") return;
      const requestId = ++availabilityRequest;
      clearTimeout(availabilityTimer);
      availabilityTimer = setTimeout(async () => {
      const name = $("subdomain").value.trim();
      if (!name) return;
      try {
        if (editBaseline && name === editBaseline.subdomain) { $("availability").textContent = locale === "en" ? "Your current address" : msg("当前连接使用的地址"); return; }
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
      if (wizardActive && wizardStep < 3) { nextWizardStep(); return; }
      if (wizardActive && createdConnection) return;
      if (wizardActive && (![0, 1, 2].every(validateWizardPanel) || !targetMayProceed())) return;
      const selected = protocols[$("protocol").value] || protocols.http;
      const blocked = creationBlock(selected);
      if (blocked) { $("edit-error").textContent = blocked; return; }
      if (!$("editor-form").reportValidity()) return;
      await runAction($("save"), async () => {
      $("edit-error").textContent = "";
      const currentNavigation = navigationRevision;
      const payload = { name: $("name").value, subdomain: $("subdomain").value, local_host: $("host").value.trim(), local_port: Number($("port").value), local_scheme: $("scheme").value, enabled: $("enabled").checked };
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
          const revision = navigationRevision;
          $("wizard-back").disabled = true; $("cancel").disabled = true;
          try {
            const result = await api("/local/connections", { method: "POST", body: JSON.stringify(payload) });
            if (revision !== navigationRevision) return;
            if (wizardActive) { createdConnection = result; renderWizard(false); $("wizard-result-state").scrollIntoView({ block: "nearest" }); return; }
          } finally { $("wizard-back").disabled = false; $("cancel").disabled = false; }
        }
        await showHome();
      } catch (error) {
        if (currentNavigation !== navigationRevision) return;
        $("edit-error").textContent = error.message;
        if (error.code === "VERSION_CONFLICT" || /VERSION_CONFLICT/.test(error.message)) {
          $("edit-error").textContent = t("conflict");
          const latest = document.createElement("button"); latest.type = "button"; latest.className = "secondary"; latest.textContent = t("retryLatest");
          latest.onclick = () => runAction(latest, async () => {
            const data = await api("/local/connections"); const item = data.items.find((c) => c.id === $("edit-id").value);
            if (!item) throw new Error(t("failed")); editVersion = item.version;
            $("edit-error").textContent = locale === "en" ? "Latest version loaded. Review your changes and save again." : msg("已读取最新版本。输入保持不变，请核对并重新保存。");
          }, "edit-error");
          $("edit-error").append(latest);
        }
      }
      }, "edit-error");
    };
    let remoteHostLoading = false, remoteHostListSignature = "", remoteFileSignature = "", remoteHostGeneration = 0, assistSecret = null, lastAssistInvites = [];
    let remoteHostAbort = new AbortController();
    function resetRemoteHostUI() {
      remoteHostGeneration++; remoteHostAbort.abort(); remoteHostAbort = new AbortController();
      localAccessID = ""; localDeviceID = ""; accountDevices = []; ++devicesRevision;
      if ($("device-rename").open) closeRename();
      remoteHostListSignature = ""; remoteFileSignature = "";
      assistSecret = null; lastAssistInvites = [];
      $("rd-assist-secret").replaceChildren(); $("rd-assist-list").replaceChildren(); $("rd-assist-error").textContent = "";
      $("rd-assist-create").disabled = true;
      $("rd-host-password").value = "";
      $("rd-host-pending").replaceChildren(); $("rd-host-grants").replaceChildren();
      $("rd-host-files").replaceChildren();
      $("rd-access-error").textContent = "";
      $("rd-legacy-trust").classList.add("hidden");
      for (const id of ["enable", "disable", "stop"]) $("rd-host-" + id).disabled = true;
    }
    const remotePermissionNames = {
      view: msg("屏幕 / Screen"), "input.keyboard": msg("键盘 / Keyboard"), "input.pointer": msg("鼠标 / Pointer"), "input.text": msg("文字输入 / Text input"),
      "audio.system": msg("系统声音 / System audio"), "audio.microphone": msg("麦克风回传 / Microphone"), "clipboard.read": msg("读取本机剪贴板 / Read local clipboard"),
      "clipboard.write": msg("写入本机剪贴板 / Write local clipboard"), "files.send": msg("发送文件到本机 / Send files here"), "files.receive": msg("从本机接收文件 / Receive files")
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
        title.textContent = event.kind === "session" ? msg("远程会话请求 / Session request") : msg("配对请求 / Pairing request");
        detail.textContent = `${event.controller_endpoint_id} · ${event.controller_thumbprint || ""}`; detail.style.overflowWrap = "anywhere";
        scopes.textContent = (event.permissions || []).map(name => remotePermissionNames[name] || name).join(" · ");
        box.append(title, detail, scopes);
        if (event.display_code) {
          const code = document.createElement("p"); code.textContent = `${msg("核对码 / Compare code: ")}${event.display_code}${msg("。请在控制端核对一致后确认。")}`; box.append(code);
        } else {
          // Long-term trust is no longer offered here; the fixed password replaces it.
          const longTerm = event.mode === "persistent" && event.kind === "pairing";
          const mode = document.createElement("p"); mode.textContent = longTerm ? msg("本机不再提供长期授权，请让对方改用固定密码连接。") : msg("仅本次会话 / This session only"); box.append(mode);
          const data = {id:event.id,kind:event.kind,permissions:event.permissions,mode:event.mode,connection_epoch:event.connection_epoch,state_version:event.state_version};
          if (!longTerm) actions.append(remoteActionButton(msg("允许以上权限 / Allow listed permissions"), "approve", data));
          actions.append(remoteActionButton(msg("拒绝 / Reject"), "reject", data, true));
          box.append(actions);
        }
        $("rd-host-pending").append(box);
      }
      for (const grant of state.grants || []) {
        if (grant.revoked || Date.parse(grant.expires_at) <= Date.now()) continue;
        const row = document.createElement("div"), detail = document.createElement("p"); row.className = "settings-card";
        detail.textContent = `${grant.mode === "persistent" ? msg("旧版长期授权 · ") : msg("单次授权 · ")}${grant.controller_endpoint_id} · ${(grant.permissions || []).map(name => remotePermissionNames[name] || name).join(" · ")} · ${new Date(grant.expires_at).toLocaleString(locale)}`;
        detail.style.overflowWrap = "anywhere";
        row.append(detail, remoteActionButton(msg("撤销授权并断开 / Revoke and disconnect"), "revoke", {id:grant.id}, true)); $("rd-host-grants").append(row);
      }
    }
    function renderAssistInvites(invites) {
      lastAssistInvites = invites || [];
      const secretBox = $("rd-assist-secret"); secretBox.replaceChildren();
      if (assistSecret && Date.parse(assistSecret.expires_at) > Date.now() && !lastAssistInvites.some(item => item.id === assistSecret.id && item.state !== "active")) {
        secretBox.classList.remove("hidden");
        const heading = document.createElement("strong"); heading.textContent = msg("仅本次显示，请安全地发送给对方");
        const code = document.createElement("p"); code.textContent = `${msg("设备 ID：")}${assistSecret.device_id}`;
        const password = document.createElement("p"); password.textContent = `${msg("临时密码：")}${assistSecret.temporary_password}`;
        const copy = document.createElement("button"); copy.type = "button"; copy.className = "secondary"; copy.textContent = msg("复制协助信息");
        copy.onclick = () => navigator.clipboard.writeText(`${msg("设备 ID：")}${assistSecret.device_id}${msg("\n临时密码：")}${assistSecret.temporary_password}`).catch(() => {});
        secretBox.append(heading, code, password, copy);
      } else { assistSecret = null; secretBox.classList.add("hidden"); }
      const list = $("rd-assist-list"); list.replaceChildren();
      for (const invite of lastAssistInvites) {
        const row = document.createElement("div"); row.className = "remote-assist-invite";
        const detail = document.createElement("span"); detail.textContent = `${invite.device_id} · ${invite.state === "redeemed" ? msg("已使用") : msg("等待连接")} · ${new Date(invite.expires_at).toLocaleString(locale)}`;
        const revoke = document.createElement("button"); revoke.type = "button"; revoke.className = "danger"; revoke.textContent = msg("撤销");
        revoke.onclick = () => runAction(revoke, async () => { await remoteHostAction("revoke_invite", {id:invite.id}); if (assistSecret?.id === invite.id) assistSecret = null; renderAssistInvites(lastAssistInvites.filter(item => item.id !== invite.id)); }, "rd-assist-error");
        row.append(detail, revoke); list.append(row);
      }
    }
    function renderAccessRequests(requests) {
      // Go encodes an empty slice as null; a default parameter only covers undefined.
      requests = requests || [];
      const list = $("rd-access-requests"); list.replaceChildren();
      if (!requests.length) { const empty = document.createElement("p"); empty.className = "muted"; empty.textContent = msg("暂无请求"); list.append(empty); return; }
      for (const request of requests) {
        const row = document.createElement("div"), detail = document.createElement("div"), actions = document.createElement("div");
        row.className = "remote-access-request"; actions.className = "remote-access-request-actions";
        const name = document.createElement("strong"), expiry = document.createElement("small");
        name.textContent = request.controller_endpoint_id; expiry.textContent = `${msg("有效至 ")}${new Date(request.expires_at).toLocaleTimeString(locale)}`;
        detail.append(name, expiry);
        const approve = document.createElement("button"), reject = document.createElement("button");
        approve.type = reject.type = "button"; approve.textContent = msg("批准本次连接"); reject.textContent = msg("拒绝"); reject.className = "danger";
        approve.onclick = () => runAction(approve, () => remoteHostAction("approve_access_request", { id: request.id }), "rd-access-error");
        reject.onclick = () => runAction(reject, () => remoteHostAction("reject_access_request", { id: request.id }), "rd-access-error");
        actions.append(approve, reject); row.append(detail, actions); list.append(row);
      }
    }
    function renderRemoteFiles(files) {
      files = files || {};
      const signature = JSON.stringify(files);
      if (signature === remoteFileSignature) return;
      remoteFileSignature = signature;
      const container = $("rd-host-files"); container.replaceChildren();
      if (!files.session_id || !files.can_send && !files.can_receive) return;
      const title = document.createElement("h3"), help = document.createElement("p");
      title.textContent = msg("会话文件 / Session files");
      help.textContent = msg("文件通过当前直连传输。请先在控制端开启文件权限；本机选择文件或保存位置，不覆盖已有文件。 / Enable file transfer on the controller, then choose files or a new destination here.");
      container.append(title, help);
      const button = (label, action, id) => {
        const node = document.createElement("button"); node.type = "button"; node.className = "secondary"; node.textContent = label;
        node.onclick = () => runAction(node, async () => {
          try { await api("/local/remote/files", {method:"POST", body:JSON.stringify({action, id, session_id:files.session_id, connection_epoch:files.connection_epoch}), signal:remoteHostAbort.signal}); }
          finally { void refreshRemoteHost(); }
        }, "rd-host-error");
        return node;
      };
      if (files.can_send) container.append(button(msg("选择多个文件发送 / Select files to send"), "send"));
      for (const item of files.items || []) {
        const row = document.createElement("div"), detail = document.createElement("p"); row.className = "settings-card";
        const phases = {offer:msg("等待选择 / Awaiting selection"), progress:msg("传输中 / Transferring"), complete:msg("已完成 / Complete"), cancelled:msg("已取消 / Cancelled"), error:msg("传输失败 / Failed")};
        detail.textContent = `${item.name || msg("文件 / File")} · ${item.outgoing ? msg("发送 / Send") : msg("接收 / Receive")} · ${phases[item.event] || item.event} · ${item.offset || 0} / ${item.size || 0} bytes${item.error_code ? " · " + item.error_code : ""}`;
        detail.style.overflowWrap = "anywhere"; row.append(detail);
        if (item.may_be_saved) { const note = document.createElement("p"); note.textContent = msg("文件可能已保存，请检查目标文件夹。 / The file may have been saved; check the destination folder."); row.append(note); }
        if (item.event === "offer" && !item.outgoing && files.can_receive) row.append(button(msg("选择保存位置 / Choose destination"), "receive", item.id));
        if (["offer", "progress"].includes(item.event)) row.append(button(msg("取消此文件 / Cancel file"), "cancel", item.id));
        container.append(row);
      }
    }
    const groupDeviceId = id => String(id).replace(/(\d{3})(?=\d)/g, "$1 ");
    async function refreshRemoteHost() {
      if (remoteHostLoading || !$("rd-host-status") || !$("login").classList.contains("hidden")) return;
      remoteHostLoading = true;
      const generation = remoteHostGeneration;
      try {
        const state = await api("/local/remote/state", {signal:remoteHostAbort.signal});
        if (generation !== remoteHostGeneration || !$("login").classList.contains("hidden")) return;
        const ready = state.capabilities?.available === true;
        const settingUp = state.setup === "pending";
        const access = state.access_profile || {};
        localAccessID = access.device_id || "";
        $("rd-host-status").textContent = !ready ? msg("此安装包没有可用的远控后端") : settingUp ? msg("正在开启远程协助…") : state.active_session_id ? msg("远程会话进行中") : state.enabled ? msg("已允许连接") : msg("远程连接已关闭");
        $("rd-host-status").dataset.active = String(ready && !!(state.active_session_id || state.enabled && state.running && !state.error_code));
        $("rd-host-code").textContent = access.device_id ? groupDeviceId(access.device_id) : state.enrolled && state.enabled ? msg("正在生成…") : "— — —";
        $("rd-host-detail").textContent = state.error_code && !settingUp ? state.error_code : "";
        $("rd-host-copy").disabled = !access.device_id;
        $("rd-host-enable").disabled = !ready || !state.enrolled || settingUp || state.enabled && state.running;
        // Show only the action that applies now: turn on, turn off, or end the live session.
        $("rd-host-enable").classList.toggle("hidden", ready && (!state.enrolled || state.enabled && state.running));
        $("rd-host-disable").disabled = !state.enabled;
        $("rd-host-disable").classList.toggle("hidden", !state.enabled);
        $("rd-host-stop").disabled = !state.active_session_id;
        $("rd-host-stop").classList.toggle("hidden", !state.active_session_id);
        // Installs that enabled the retired long-term mode keep a way to turn it off.
        $("rd-legacy-trust").classList.toggle("hidden", state.unattended_enabled !== true);
        $("rd-fixed-scope").classList.toggle("hidden", state.capabilities?.unattended_enabled === true);
        $("rd-emergency-key").value = state.emergency_key || "X";
        $("rd-fixed-save").disabled = !state.enabled || !state.running || !ready;
        const fixedActive = !!access.fixed_password_enabled && access.revision === state.fixed_revision;
        $("rd-fixed-disable").disabled = !fixedActive;
        $("rd-fixed-status").textContent = fixedActive ? msg("固定密码已启用 · 可跨账号自动连接") : access.fixed_password_enabled ? msg("服务端密码与本机授权版本不一致，请重新设置") : msg("未设置固定密码");
        renderAccessRequests(state.access_requests);
        $("rd-assist-create").disabled = !state.enabled || !state.running || !state.enrolled || !ready;
        if (!state.enabled) assistSecret = null;
        $("rd-host-enroll").classList.toggle("hidden", !ready || state.enrolled || settingUp);
        if (!$("rd-host-user").value) $("rd-host-user").value = localStorage.getItem("ht_username") || "";
        if (state.enrolled || !ready) {
          $("rd-host-password").value = "";
        }
        renderRemoteApprovals(state);
        renderAssistInvites(state.invites);
        renderRemoteFiles(state.files);
        remoteSecurity.classList.toggle("hidden", !ready || !$("rd-host-pending").childElementCount && !$("rd-host-grants").childElementCount && !$("rd-host-files").childElementCount);
        const count = (state.pending || []).filter(event => !event.display_code).length + (state.access_requests || []).length;
        $("settings-open").textContent = t("settings") + (count ? ` · ${count}${msg(" 待批准 / pending")}` : "");
      } catch {
        if (generation !== remoteHostGeneration) return;
        $("rd-host-status").textContent = msg("无法读取远控状态 / Remote status unavailable");
        $("rd-host-status").dataset.active = "false";
        for (const id of ["enable", "disable", "stop"]) $("rd-host-" + id).disabled = id === "enable";
      }
      finally { remoteHostLoading = false; }
    }
    for (const action of ["enable", "disable", "stop"]) $("rd-host-" + action).onclick = () => runAction($("rd-host-" + action), () => remoteHostAction(action), "rd-host-error");
    $("rd-legacy-disable").onclick = () => runAction($("rd-legacy-disable"), () => remoteHostAction("disable_unattended"), "rd-access-error");
    $("rd-fixed-form").onsubmit = event => {
      event.preventDefault();
      const password = $("rd-fixed-password").value;
      $("rd-fixed-password").value = "";
      return runAction($("rd-fixed-save"), () => remoteHostAction("set_fixed_password", { fixed_password: password }), "rd-access-error");
    };
    $("rd-fixed-disable").onclick = () => runAction($("rd-fixed-disable"), () => remoteHostAction("disable_fixed_password"), "rd-access-error");
    $("rd-emergency-key").onchange = () => runAction($("rd-emergency-key"), () => remoteHostAction("set_emergency_hotkey", { emergency_key: $("rd-emergency-key").value }), "rd-access-error");
    $("rd-assist-create").onclick = () => runAction($("rd-assist-create"), async () => {
      assistSecret = await remoteHostAction("create_invite");
      renderAssistInvites(lastAssistInvites);
    }, "rd-assist-error");
    $("rd-host-enroll").onsubmit = event => {
      event.preventDefault();
      return runAction($("rd-host-enroll-submit"), async () => {
        $("rd-host-error").textContent = "";
        const body = {username:$("rd-host-user").value,password:$("rd-host-password").value,trust_pin:""};
        $("rd-host-password").value = "";
        try { await remoteHostAction("enroll", body); }
        finally { body.password = ""; }
      }, "rd-host-error");
    };
    setInterval(() => { if (!document.hidden) void refreshRemoteHost(); }, 3000);
    $("nav-remote").onclick = () => showRemote().catch((error) => { $("rd-host-error").textContent = error.message; });
    $("nav-devices").onclick = () => showDevices().catch((error) => { $("devices-error").textContent = error.message; });
    $("nav-tunnels").onclick = () => showHome().catch((error) => { $("status").textContent = error.message; });
    $("nav-settings").onclick = () => showSettings().catch(error => { $("settings-error").textContent = error.message; });
    $("nav-console").onclick = () => void openConsole("", $("remote-page").classList.contains("hidden") ? "status" : "remote-open-error");
    $("sidebar-locale").onclick = () => $("locale-toggle").click();
    $("sidebar-theme").onclick = () => $("theme-toggle").click();
    $("remote-refresh").onclick = () => void refreshRemoteHost();
    $("devices-refresh").onclick = () => void loadDevices().catch((error) => { $("devices-error").textContent = error.message; });
    $("devices-search").oninput = renderAccountDevices;
    $("update-check").onclick = () => void checkUpdates();
    api("/local/state").then((state) => { if (state.enrolled) return showRemote(); }).catch(() => { $("login-error").textContent = t("failed"); });

    setInterval(() => { if (!document.hidden) showHome(true).catch(() => { $("status").textContent = t("stale"); }); }, 30000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) showHome(true).catch(() => { $("status").textContent = t("stale"); }); });
