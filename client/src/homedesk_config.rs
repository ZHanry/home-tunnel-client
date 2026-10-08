// HOMEDESK: 将双模式原子配置组与上游 RustDesk 配置实现隔离。
use hbb_common::{config::{self, keys, Config, Config2}, log};
use std::{collections::HashMap, net::SocketAddr, sync::atomic::{AtomicBool, AtomicU64, Ordering}};

pub use crate::homedesk_net::normalize_private_whitelist;
use crate::homedesk_net::{is_valid_server, normalize_source_whitelist, NetworkMode};

const NET_MODE: &str = env!("HOMEDESK_NET_MODE");
const SERVER_HOST: &str = env!("HOMEDESK_SERVER_HOST");
const RELAY_HOST: &str = ""; // HOMEDESK: No build or runtime relay override.
const SERVER_KEY: &str = env!("HOMEDESK_SERVER_KEY");
const WHITELIST_CIDR: &str = env!("HOMEDESK_WHITELIST_CIDR");
const SOURCE_CIDR: &str = env!("HOMEDESK_SOURCE_CIDR");
const CONSOLE_ENABLED: &str = env!("HOMEDESK_CONSOLE_ENABLED");
const CONSOLE_TRUSTED_PATH: &str = env!("HOMEDESK_CONSOLE_TRUSTED_PATH");

const MODE_KEY: &str = "homedesk-net-mode";
const PROFILE_PREFIX: &str = "homedesk-profile-";
const PROFILE_SCHEMA_KEY: &str = "homedesk-profile-schema";
static PROFILE_CONFIRMED: AtomicBool = AtomicBool::new(true);
static PORTAL_PERMISSION_EPOCH: AtomicU64 = AtomicU64::new(0);


// HOMEDESK: Remote profile confirmation has no authority over tunnel accounts or Agents.
pub struct PortalProfileUpdate;
pub fn begin_portal_profile_update() -> PortalProfileUpdate { PortalProfileUpdate }
pub fn mark_profile_unconfirmed() { PROFILE_CONFIRMED.store(false, Ordering::SeqCst); }
pub fn mark_profile_confirmed() { PROFILE_CONFIRMED.store(true, Ordering::SeqCst); }

pub fn invalidate_portal_permission() {
    PORTAL_PERMISSION_EPOCH.fetch_add(1, Ordering::SeqCst);
    crate::homedesk_tunnel_runtime::stop_all(); // HOMEDESK: 批准地址变更同步终止旧 Agent。
}

// HOMEDESK: 记住记录不能自行授予端点许可，批准地址须来自本机显式填写的 HTTPS origin。
pub fn normalize_portal_origin(value: &str) -> Option<String> {
    if value.trim() != value || value.chars().any(|c| c.is_control() || c.is_whitespace() || c == '\\') { return None; }
    let url = reqwest::Url::parse(value).ok()?;
    if url.scheme() != "https" || url.host_str().is_none() || !url.username().is_empty()
        || url.password().is_some() || url.query().is_some() || url.fragment().is_some()
        || !matches!(url.path(), "" | "/") || url.port_or_known_default() == Some(0) { return None; }
    Some(url.origin().ascii_serialization())
}

#[derive(Clone, Debug)]
pub struct NetworkProfile {
    pub mode: NetworkMode,
    pub server: String,
    pub relay: String,
    pub key: String,
    pub family_cidr: String,
    pub source_cidr: String,
}

fn profile_key(mode: NetworkMode, field: &str) -> String {
    format!("{PROFILE_PREFIX}{}-{field}", mode.as_str())
}

fn compiled_mode() -> NetworkMode { NetworkMode::parse(NET_MODE).unwrap_or(NetworkMode::LanOnly) }

fn validate_key(value: &str) -> bool {
    crate::common::decode64(value).map_or(false, |decoded| decoded.len() == 32)
}

fn validate_profile(profile: &NetworkProfile) -> Result<(), String> {
    if !is_valid_server(&profile.server, profile.mode) { return Err("ID 服务器不符合当前网络模式".to_owned()); }
    if !profile.relay.is_empty() { return Err("远程控制固定 P2P，不能配置中继服务器".to_owned()); }
    if !validate_key(&profile.key) { return Err("服务器公钥必须是 32 字节 hbbs Base64 公钥".to_owned()); }
    if normalize_private_whitelist(&profile.family_cidr).is_none() { return Err("家庭 CIDR 必须完整位于 RFC1918 私网".to_owned()); }
    if normalize_source_whitelist(&profile.source_cidr).is_none() { return Err("公网来源限制必须是有效 IPv4 CIDR，且不能允许全部地址".to_owned()); }
    Ok(())
}

pub fn active_mode() -> NetworkMode {
    if !PROFILE_CONFIRMED.load(Ordering::SeqCst) { return NetworkMode::LanOnly; }
    NetworkMode::parse(&Config::get_option(MODE_KEY)).unwrap_or(NetworkMode::LanOnly)
}

pub fn active_profile() -> NetworkProfile {
    let mode = active_mode();
    if !PROFILE_CONFIRMED.load(Ordering::SeqCst) {
        return NetworkProfile { mode, server: String::new(), relay: String::new(), key: String::new(), family_cidr: String::new(), source_cidr: String::new() };
    }
    NetworkProfile {
        mode,
        server: Config::get_option(&profile_key(mode, "server")),
        relay: String::new(), // HOMEDESK: Ignore any legacy/imported relay.
        key: Config::get_option(&profile_key(mode, "key")),
        family_cidr: Config::get_option(&profile_key(mode, "family-cidr")),
        source_cidr: Config::get_option(&profile_key(mode, "source-cidr")),
    }
}

pub fn save_network_profile(profile: NetworkProfile) -> Result<(), String> {
    validate_profile(&profile)?;
    // HOMEDESK: Saving remote settings does not invalidate independent tunnel permission.
    let previous = Config2::get();
    let mut options = Config::get_options();
    options.insert(profile_key(profile.mode, "server"), profile.server.clone());
    options.insert(profile_key(profile.mode, "relay"), profile.relay.clone());
    options.insert(profile_key(profile.mode, "key"), profile.key.clone());
    options.insert(profile_key(profile.mode, "family-cidr"), profile.family_cidr.clone());
    options.insert(profile_key(profile.mode, "source-cidr"), profile.source_cidr.clone());
    options.insert(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.to_owned(), profile.server);
    options.insert(keys::OPTION_RELAY_SERVER.to_owned(), profile.relay);
    options.insert(keys::OPTION_KEY.to_owned(), profile.key);
    let ingress = if profile.mode == NetworkMode::LanOnly { profile.family_cidr } else { profile.source_cidr };
    options.insert(keys::OPTION_WHITELIST.to_owned(), ingress);
    options.insert(PROFILE_SCHEMA_KEY.to_owned(), "1".to_owned());
    // HOMEDESK: 模式最后写入同一份 options，并由 Config 一次落盘；校验失败不会替换旧组。
    options.insert(MODE_KEY.to_owned(), profile.mode.as_str().to_owned());
    Config::set_options(options);
    let current = Config2::get();
    let stored: Config2 = config::load_path(Config2::file());
    if stored.options != current.options {
        Config2::set(previous);
        return Err("网络配置未能持久化，已回滚内存中的新配置".to_owned());
    }
    Ok(())
}

pub fn apply() {
    // HOMEDESK: 在注入新默认值前读取旧配置；合法旧高级设置只迁入 lan_only 一次。
    let stored_options = Config2::get().options;
    let had_legacy_options = !stored_options.is_empty();
    let existing_mode = stored_options.get(MODE_KEY).cloned().unwrap_or_default();
    let existing_schema = stored_options.get(PROFILE_SCHEMA_KEY).cloned().unwrap_or_default();
    let legacy_server = stored_options.get(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER).cloned().unwrap_or_default();
    let legacy_key = stored_options.get(keys::OPTION_KEY).cloned().unwrap_or_default();
    let legacy_cidr = stored_options.get(keys::OPTION_WHITELIST).cloned().unwrap_or_default();
    config::EXE_RENDEZVOUS_SERVER.write().unwrap().clear();
    Config::set_socks(None); // HOMEDESK: 代理不能把信令/中继授权扩展到未验证的代理解析目标。
    *config::PROD_RENDEZVOUS_SERVER.write().unwrap() = SERVER_HOST.to_owned();

    let mode = compiled_mode();
    let mut defaults = config::DEFAULT_SETTINGS.write().unwrap();
    defaults.insert(MODE_KEY.to_owned(), mode.as_str().to_owned());
    defaults.insert(profile_key(mode, "server"), SERVER_HOST.to_owned());
    defaults.insert(profile_key(mode, "relay"), RELAY_HOST.to_owned());
    defaults.insert(profile_key(mode, "key"), SERVER_KEY.to_owned());
    defaults.insert(profile_key(mode, "family-cidr"), WHITELIST_CIDR.to_owned());
    defaults.insert(profile_key(mode, "source-cidr"), SOURCE_CIDR.to_owned());
    defaults.insert(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.to_owned(), SERVER_HOST.to_owned());
    defaults.insert(keys::OPTION_RELAY_SERVER.to_owned(), RELAY_HOST.to_owned());
    defaults.insert(keys::OPTION_KEY.to_owned(), SERVER_KEY.to_owned());
    defaults.insert(keys::OPTION_WHITELIST.to_owned(), if mode == NetworkMode::LanOnly { WHITELIST_CIDR } else { SOURCE_CIDR }.to_owned());
    drop(defaults);

    if existing_schema.is_empty() && existing_mode.is_empty() && had_legacy_options {
        let legacy = NetworkProfile {
            mode: NetworkMode::LanOnly,
            server: legacy_server,
            relay: String::new(), // HOMEDESK: Do not migrate relay defaults.
            key: if legacy_key.is_empty() { SERVER_KEY.to_owned() } else { legacy_key },
            family_cidr: legacy_cidr,
            source_cidr: String::new(),
        };
        if let Err(error) = validate_profile(&legacy) {
            // HOMEDESK: 不完整/非法旧配置隔离在 lan_only 组，保持不可连接，绝不落到新产物的公网默认组。
            let mut options = Config::get_options();
            options.insert(MODE_KEY.to_owned(), NetworkMode::LanOnly.as_str().to_owned());
            options.insert(PROFILE_SCHEMA_KEY.to_owned(), "1".to_owned());
            options.insert(profile_key(NetworkMode::LanOnly, "server"), legacy.server);
            options.insert(profile_key(NetworkMode::LanOnly, "relay"), legacy.relay);
            options.insert(profile_key(NetworkMode::LanOnly, "key"), legacy.key);
            options.insert(profile_key(NetworkMode::LanOnly, "family-cidr"), legacy.family_cidr);
            options.insert(profile_key(NetworkMode::LanOnly, "source-cidr"), String::new());
            Config::set_options(options);
            log::error!("HomeDesk 旧网络配置迁移失败，已保持 lan_only 且拒绝连接：{error}");
        } else if let Err(error) = save_network_profile(legacy) {
            log::error!("HomeDesk 旧网络配置保存失败，未切换模式：{error}");
        }
    }
    if existing_schema.is_empty() && !had_legacy_options {
        let mut options = Config::get_options();
        options.insert(PROFILE_SCHEMA_KEY.to_owned(), "1".to_owned());
        Config::set_options(options);
    }

    config::DEFAULT_LOCAL_SETTINGS.write().unwrap().insert(keys::OPTION_LANGUAGE.into(), "zh-cn".into());
    let mut hard = config::HARD_SETTINGS.write().unwrap();
    for key in ["disable-account", "disable-ab"] { hard.insert(key.into(), "Y".into()); }
    drop(hard);

    let profile = active_profile();
    { // HOMEDESK: Clear transport overrides even when the profile is unconfigured.
        let mut options = Config::get_options();
        options.insert(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.to_owned(), profile.server);
        options.insert(keys::OPTION_RELAY_SERVER.to_owned(), profile.relay);
        options.insert(keys::OPTION_KEY.to_owned(), profile.key);
        options.insert(keys::OPTION_WHITELIST.to_owned(), if profile.mode == NetworkMode::LanOnly { profile.family_cidr } else { profile.source_cidr });
        Config::set_options(options);
    }

    let mut enforced = config::OVERWRITE_SETTINGS.write().unwrap();
    enforced.insert(keys::OPTION_API_SERVER.to_owned(), String::new());
    enforced.insert(keys::OPTION_ALLOW_AUTO_UPDATE.to_owned(), "N".to_owned());
    for key in ["hide-help-cards", "hide-proxy-settings", "hide-websocket-settings", "hide-remote-printer-settings"] { enforced.insert(key.into(), "Y".into()); }
    enforced.insert(keys::OPTION_ALLOW_INSECURE_TLS_FALLBACK.to_owned(), "N".to_owned());
    // HOMEDESK: Require direct applies to old config, URI /r, per-peer options and proxy paths.
    enforced.insert(keys::OPTION_RELAY_SERVER.to_owned(), String::new());
    enforced.insert("force-always-relay".into(), "N".into());
    enforced.insert("allow-websocket".into(), "N".into());
    drop(enforced);

    let mut local = config::OVERWRITE_LOCAL_SETTINGS.write().unwrap();
    local.insert(keys::OPTION_ENABLE_CHECK_UPDATE.to_owned(), "N".to_owned());
    // HOMEDESK: UDP/KCP 会话与 IPv6 未过兼容门禁，保持关闭；不设置 disable-udp，保留 hbbs UDP 注册心跳。
    local.insert(keys::OPTION_ENABLE_UDP_PUNCH.to_owned(), "N".to_owned());
    local.insert(keys::OPTION_ENABLE_IPV6_PUNCH.to_owned(), "N".to_owned());
    local.insert("homedesk-console-url".into(), option_env!("HOMEDESK_CONSOLE_URL").unwrap_or_default().into());
    local.insert("homedesk-console-token".into(), option_env!("HOMEDESK_CONSOLE_TOKEN").unwrap_or_default().into());
}

pub fn public_services_disabled() -> bool { true }
pub fn pure_lan_enabled() -> bool { active_mode() == NetworkMode::LanOnly }
pub fn requires_secure_session() -> bool { true }
pub fn require_direct() -> bool { true }
pub fn remote_profile_ready() -> bool { validate_profile(&active_profile()).is_ok() }
pub fn public_stun_allowed() -> bool { false }
// HOMEDESK: HTTPS portal approval/account credentials authorize tunneling independently.
pub fn home_tunnel_allowed() -> bool {
    crate::homedesk_net::home_tunnel_allowed(active_mode(), PROFILE_CONFIRMED.load(Ordering::SeqCst))
}
pub fn home_tunnel_permission() -> String {
    let epoch = PORTAL_PERMISSION_EPOCH.load(Ordering::SeqCst);
    if !home_tunnel_allowed() || epoch != PORTAL_PERMISSION_EPOCH.load(Ordering::SeqCst) { return String::new(); }
    epoch.to_string()
}
pub fn console_allowed() -> bool {
    if !PROFILE_CONFIRMED.load(Ordering::SeqCst) { return false; }
    crate::homedesk_net::console_allowed(
        active_mode(),
        CONSOLE_ENABLED == "true",
        CONSOLE_TRUSTED_PATH == "true",
    )
}

pub fn console_configured() -> bool { CONSOLE_ENABLED == "true" }

pub fn allows_http(url: &str) -> bool {
    let Ok(url) = reqwest::Url::parse(url) else { return false; };
    if !matches!(url.scheme(), "http" | "https") || !url.username().is_empty() || url.password().is_some() { return false; }
    let Some(host) = url.host_str() else { return false; };
    // HOMEDESK: 两种模式的普通 HTTP/下载都只允许家庭 CIDR；公网授权只供信令、中继和当前会话候选使用。
    crate::homedesk_net::address_in_whitelist(host, &active_profile().family_cidr)
}

pub fn rendezvous_servers() -> Vec<String> {
    let configured = active_profile().server;
    if remote_profile_ready() { vec![configured] } else { Vec::new() }
}

// HOMEDESK: Fail before DNS, signaling or dial for every relay candidate.
pub fn relay_allowed(candidate: &str) -> bool { crate::homedesk_net::relay_allowed(candidate) }
pub async fn normalize_relay_candidate(_candidate: &str) -> Result<String, String> {
    Err("远程控制固定 P2P，禁止中继".to_owned())
}

pub async fn resolve_configured_endpoint(endpoint: &str, default_port: i32, relay: bool) -> Result<SocketAddr, String> {
    let profile = active_profile();
    // HOMEDESK: No relay DNS resolution, including configured/legacy candidates.
    if relay { return Err("远程控制固定 P2P，禁止中继解析".to_owned()); }
    if !remote_profile_ready() { return Err("请先配置并确认自建 hbbs 地址与公钥".to_owned()); }
    let configured = &profile.server;
    let candidate = hbb_common::socket_client::check_port(endpoint.to_owned(), default_port);
    let configured = hbb_common::socket_client::check_port(configured.to_owned(), default_port);
    if !candidate.eq_ignore_ascii_case(&configured) {
        return Err("目标不属于当前原子配置组".to_owned());
    }
    let addresses = hbb_common::tokio::net::lookup_host(&candidate).await
        .map_err(|error| format!("无法解析已配置地址：{error}"))?;
    let resolved = addresses
        .filter(|address| address.is_ipv4() && is_valid_server(&address.to_string(), profile.mode))
        .next()
        .ok_or_else(|| "已配置域名未解析到允许的 IPv4 地址".to_owned());
    resolved
}

pub fn source_allowed(endpoint: std::net::SocketAddr) -> bool {
    let profile = active_profile();
    profile.mode == NetworkMode::LanOnly
        || crate::homedesk_net::source_endpoint_allowed(endpoint, &profile.source_cidr)
}

pub fn sanitize_options(options: &mut HashMap<String, String>) {
    let current = Config::get_options();
    options.retain(|key, _| !key.starts_with(PROFILE_PREFIX));
    for (key, value) in current.iter().filter(|(key, _)| key.starts_with(PROFILE_PREFIX)) {
        options.insert(key.clone(), value.clone());
    }
    let profile = active_profile();
    for (key, value) in [
        (PROFILE_SCHEMA_KEY, "1".to_owned()),
        (MODE_KEY, profile.mode.as_str().to_owned()),
        (keys::OPTION_CUSTOM_RENDEZVOUS_SERVER, profile.server),
        (keys::OPTION_RELAY_SERVER, profile.relay),
        (keys::OPTION_KEY, profile.key),
        (keys::OPTION_WHITELIST, if profile.mode == NetworkMode::LanOnly { profile.family_cidr } else { profile.source_cidr }),
    ] { options.insert(key.to_owned(), value); }
    for key in [keys::OPTION_API_SERVER, keys::OPTION_ALLOW_AUTO_UPDATE, keys::OPTION_ALLOW_INSECURE_TLS_FALLBACK, "force-always-relay", "allow-websocket"] { options.remove(key); }
    options.insert(keys::OPTION_RELAY_SERVER.to_owned(), String::new());
    // HOMEDESK: Previously stored relay profile fields cannot survive an options import.
    for (key, value) in options.iter_mut() {
        if key.starts_with(PROFILE_PREFIX) && key.ends_with("-relay") { value.clear(); }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn approved_portal_origin_is_https_and_canonical() {
        assert_eq!(normalize_portal_origin("https://CONSOLE.example.com:443/"), Some("https://console.example.com".to_owned()));
        assert_eq!(normalize_portal_origin("https://console.example.com:8443"), Some("https://console.example.com:8443".to_owned()));
        for invalid in ["http://console.example.com", "https://user@console.example.com", "https://console.example.com/api/v1", "https://console.example.com?token=test", "https://console.example.com#fragment", " https://console.example.com", "https://console.example.com:0", "https://console.example.com\\"] {
            assert!(normalize_portal_origin(invalid).is_none());
        }
    }
    #[test]
    fn imported_options_cannot_override_security_boundary() {
        let mut options = HashMap::from([(MODE_KEY.to_owned(), "self_hosted".to_owned()), (keys::OPTION_KEY.to_owned(), "key".to_owned()), (profile_key(NetworkMode::SelfHosted, "server"), "evil.example.com".to_owned())]);
        sanitize_options(&mut options);
        assert_eq!(options.get(MODE_KEY).map(String::as_str), Some(active_mode().as_str()));
    }
}
