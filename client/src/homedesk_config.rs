// HOMEDESK: 将家庭内网默认值与上游 RustDesk 配置实现隔离。
use hbb_common::config::{self, keys};
use std::collections::HashMap;

pub use crate::homedesk_net::{is_private_rendezvous_server, normalize_private_whitelist};

const SERVER_HOST: &str = env!("HOMEDESK_SERVER_HOST");
const SERVER_KEY: &str = env!("HOMEDESK_SERVER_KEY");
const WHITELIST_CIDR: &str = env!("HOMEDESK_WHITELIST_CIDR");
const PURE_LAN_DEFAULT: &str = env!("HOMEDESK_PURE_LAN_DEFAULT");

pub fn apply() {
    let executable_server = config::EXE_RENDEZVOUS_SERVER.read().unwrap().clone();
    if public_services_disabled() && !executable_server.is_empty() {
        config::EXE_RENDEZVOUS_SERVER.write().unwrap().clear();
    }
    *config::PROD_RENDEZVOUS_SERVER.write().unwrap() = SERVER_HOST.to_owned();

    let mut defaults = config::DEFAULT_SETTINGS.write().unwrap();
    defaults.insert(
        keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.to_owned(),
        SERVER_HOST.to_owned(),
    );
    defaults.insert(keys::OPTION_WHITELIST.to_owned(), WHITELIST_CIDR.to_owned());
    drop(defaults);

    config::DEFAULT_SETTINGS.write().unwrap().insert("homedesk-pure-lan".into(), "Y".into());
    config::DEFAULT_LOCAL_SETTINGS.write().unwrap().insert(keys::OPTION_LANGUAGE.into(), "zh-cn".into());
    let mut hard = config::HARD_SETTINGS.write().unwrap();
    for key in ["disable-account", "disable-ab"] { hard.insert(key.into(), "Y".into()); }
    drop(hard);

    let saved_server = config::Config::get_option(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER);
    if !is_private_rendezvous_server(&saved_server) {
        config::Config::set_option(
            keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.to_owned(),
            SERVER_HOST.to_owned(),
        );
    }
    let saved_whitelist = config::Config::get_option(keys::OPTION_WHITELIST);
    if let Some(normalized) = normalize_private_whitelist(&saved_whitelist) {
        if normalized != saved_whitelist {
            config::Config::set_option(keys::OPTION_WHITELIST.to_owned(), normalized);
        }
    } else {
        config::Config::set_option(keys::OPTION_WHITELIST.to_owned(), WHITELIST_CIDR.to_owned());
    }

    let mut enforced = config::OVERWRITE_SETTINGS.write().unwrap();
    enforced.insert(keys::OPTION_KEY.to_owned(), SERVER_KEY.to_owned());
    enforced.insert(keys::OPTION_API_SERVER.to_owned(), String::new());
    enforced.insert(keys::OPTION_RELAY_SERVER.to_owned(), String::new());
    enforced.insert(keys::OPTION_ALLOW_AUTO_UPDATE.to_owned(), "N".to_owned());
    for key in ["hide-help-cards", "hide-proxy-settings", "hide-websocket-settings", "hide-remote-printer-settings"] {
        enforced.insert(key.into(), "Y".into());
    }
    enforced.insert(
        keys::OPTION_ALLOW_INSECURE_TLS_FALLBACK.to_owned(),
        "N".to_owned(),
    );
    drop(enforced);

    config::OVERWRITE_LOCAL_SETTINGS
        .write()
        .unwrap()
        .insert(keys::OPTION_ENABLE_CHECK_UPDATE.to_owned(), "N".to_owned());
    // 家庭设备墙通过现有只读配置桥读取编译期值，避免新增生成式 FFI 接口。
    // 访问口令仅保存在内存覆盖项，不写入用户配置文件或日志。
    let mut local = config::OVERWRITE_LOCAL_SETTINGS.write().unwrap();
    local.insert("homedesk-console-url".into(), option_env!("HOMEDESK_CONSOLE_URL").unwrap_or_default().into());
    local.insert("homedesk-console-token".into(), option_env!("HOMEDESK_CONSOLE_TOKEN").unwrap_or_default().into());
}

pub fn public_services_disabled() -> bool {
    PURE_LAN_DEFAULT == "true"
}

pub fn pure_lan_enabled() -> bool { config::Config::get_option("homedesk-pure-lan") != "N" }

pub fn allows_http(url: &str) -> bool {
    if !pure_lan_enabled() { return true; }
    let Ok(url) = reqwest::Url::parse(url) else { return false; };
    if !matches!(url.scheme(), "http" | "https") || !url.username().is_empty() || url.password().is_some() { return false; }
    url.host_str().map_or(false, |host| crate::homedesk_net::address_in_whitelist(host, &config::Config::get_option(keys::OPTION_WHITELIST)))
}

pub const fn compiled_server() -> &'static str {
    SERVER_HOST
}

pub const fn compiled_key() -> &'static str {
    SERVER_KEY
}

pub fn rendezvous_servers() -> Vec<String> {
    let mut servers: Vec<String> = config::Config::get_rendezvous_servers()
        .into_iter()
        .filter(|server| is_private_rendezvous_server(server))
        .collect();
    if servers.is_empty() {
        servers.push(SERVER_HOST.to_owned());
    }
    servers
}

pub fn sanitize_options(options: &mut HashMap<String, String>) {
    if let Some(server) = options.get(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER) {
        if !is_private_rendezvous_server(server) {
            options.remove(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER);
        }
    }
    if let Some(whitelist) = options.get(keys::OPTION_WHITELIST).cloned() {
        match normalize_private_whitelist(&whitelist) {
            Some(normalized) => {
                options.insert(keys::OPTION_WHITELIST.to_owned(), normalized);
            }
            None => {
                options.remove(keys::OPTION_WHITELIST);
            }
        }
    }
    options.remove(keys::OPTION_KEY);
    options.remove(keys::OPTION_API_SERVER);
    options.remove(keys::OPTION_RELAY_SERVER);
    options.remove(keys::OPTION_ALLOW_AUTO_UPDATE);
    options.remove(keys::OPTION_ALLOW_INSECURE_TLS_FALLBACK);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn imported_options_cannot_override_security_boundary() {
        let mut options = HashMap::from([
            (
                keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.to_owned(),
                "8.8.8.8".to_owned(),
            ),
            (keys::OPTION_WHITELIST.to_owned(), "0.0.0.0".to_owned()),
            (keys::OPTION_KEY.to_owned(), "public-key".to_owned()),
        ]);
        sanitize_options(&mut options);
        assert!(options.is_empty());
    }
}
