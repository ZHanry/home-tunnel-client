// HOMEDESK: 隔离读取单仓库构建配置，避免把家庭网络参数散落到上游代码。
use std::{collections::HashMap, env, fs, net::Ipv4Addr, path::PathBuf};

#[derive(Debug, PartialEq)]
struct BrandConfig {
    app_name: String,
    config_namespace: String,
    executable_name: String,
    package_name: String,
}

#[derive(Debug, PartialEq)]
struct BuildConfig {
    brand: BrandConfig,
    net_mode: String,
    server_host: String,
    relay_host: String,
    server_key: String,
    whitelist_cidr: String,
    source_cidr: String,
    console_enabled: bool,
    console_url: String,
    console_token: String,
    console_trusted_path: bool,
}

pub fn configure() {
    if let Err(error) = configure_inner() {
        panic!("HomeDesk 构建配置无效：{}", error);
    }
}

// HOMEDESK: 安装包外壳也从同一配置读取品牌，不重复硬编码资源字符串。
pub fn resource_brand() -> Result<(String, String), String> {
    println!("cargo:rerun-if-env-changed=HOMEDESK_CONFIG_PATH");
    let source = resolve_config_path()?;
    println!("cargo:rerun-if-changed={}", source.display());
    let content = fs::read_to_string(&source).map_err(|_| "无法读取品牌构建配置".to_owned())?;
    let config = parse_config(&content)?;
    Ok((config.brand.app_name, config.brand.executable_name))
}

fn configure_inner() -> Result<(), String> {
    println!("cargo:rerun-if-env-changed=HOMEDESK_CONFIG_PATH");
    let source = resolve_config_path()?;
    println!("cargo:rerun-if-changed={}", source.display());
    let content = fs::read_to_string(&source)
        .map_err(|error| format!("无法读取 {}：{error}", source.display()))?;
    let config = parse_config(&content)?;

    println!(
        "cargo:rustc-env=HOMEDESK_APP_NAME={}",
        config.brand.app_name
    );
    println!("cargo:rustc-env=HOMEDESK_CONFIG_NAMESPACE={}", config.brand.config_namespace);
    println!(
        "cargo:rustc-env=HOMEDESK_EXECUTABLE_NAME={}",
        config.brand.executable_name
    );
    println!(
        "cargo:rustc-env=HOMEDESK_PACKAGE_NAME={}",
        config.brand.package_name
    );
    println!(
        "cargo:rustc-env=HOMEDESK_NET_MODE={}",
        config.net_mode
    );
    println!(
        "cargo:rustc-env=HOMEDESK_SERVER_HOST={}",
        config.server_host
    );
    println!("cargo:rustc-env=HOMEDESK_RELAY_HOST={}", config.relay_host);
    println!("cargo:rustc-env=HOMEDESK_SERVER_KEY={}", config.server_key);
    println!(
        "cargo:rustc-env=HOMEDESK_WHITELIST_CIDR={}",
        config.whitelist_cidr
    );
    println!(
        "cargo:rustc-env=HOMEDESK_SOURCE_CIDR={}",
        config.source_cidr
    );
    println!("cargo:rustc-env=HOMEDESK_CONSOLE_ENABLED={}", config.console_enabled);
    println!("cargo:rustc-env=HOMEDESK_CONSOLE_TRUSTED_PATH={}", config.console_trusted_path);
    println!("cargo:rustc-env=HOMEDESK_CONSOLE_URL={}", config.console_url);
    println!("cargo:rustc-env=HOMEDESK_CONSOLE_TOKEN={}", config.console_token);
    Ok(())
}

fn resolve_config_path() -> Result<PathBuf, String> {
    if let Some(path) = env::var_os("HOMEDESK_CONFIG_PATH") {
        return Ok(PathBuf::from(path));
    }
    let manifest_dir = env::var_os("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .ok_or_else(|| "未设置 CARGO_MANIFEST_DIR".to_owned())?;
    // HOMEDESK: 支持主 crate 与嵌套的 portable crate 共用单仓库构建配置。
    let root = manifest_dir.ancestors()
        .find(|path| path.join("build/config.toml.example").is_file())
        .ok_or_else(|| "未找到 HomeDesk 单仓库配置目录".to_owned())?;
    let local = root.join("build/config.toml");
    if local.is_file() {
        return Ok(local);
    }
    Ok(root.join("build/config.toml.example"))
}

fn parse_config(content: &str) -> Result<BuildConfig, String> {
    let mut section = "";
    let mut values = HashMap::new();
    for (index, raw_line) in content.lines().enumerate() {
        let line = strip_comment(raw_line).trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            section = line[1..line.len() - 1].trim();
            continue;
        }
        if !matches!(section, "brand" | "server" | "net" | "console") {
            continue;
        }
        let Some((key, raw_value)) = line.split_once('=') else {
            return Err(format!("第 {} 行不是键值配置", index + 1));
        };
        let key = key.trim();
        let full_key = format!("{section}.{key}");
        let value = if matches!(full_key.as_str(), "net.pure_lan_default" | "console.enabled" | "console.trusted_path") {
            match raw_value.trim() {
                "true" | "false" => raw_value.trim().to_owned(),
                _ => return Err(format!("第 {} 行必须为布尔值", index + 1)),
            }
        } else {
            parse_basic_string(raw_value.trim())
                .map_err(|error| format!("第 {} 行：{error}", index + 1))?
        };
        if !matches!(
            full_key.as_str(),
            "brand.app_name"
                | "brand.config_namespace"
                | "brand.executable_name"
                | "brand.package_name"
                | "server.host"
                | "server.relay_host"
                | "server.key"
                | "net.mode"
                | "net.whitelist_cidr"
                | "net.source_cidr"
                | "net.pure_lan_default"
                | "console.enabled"
                | "console.trusted_path"
                | "console.url"
                | "console.token"
        ) {
            return Err(format!("第 {} 行包含未知配置 {full_key}", index + 1));
        }
        if values.insert(full_key.clone(), value).is_some() {
            return Err(format!("第 {} 行重复定义 {full_key}", index + 1));
        }
    }

    let legacy_pure_lan = values.get("net.pure_lan_default").map(String::as_str);
    let net_mode = match values.get("net.mode").map(String::as_str) {
        Some("lan_only" | "self_hosted") => values["net.mode"].clone(),
        Some(_) => return Err("net.mode 仅允许 lan_only 或 self_hosted".to_owned()),
        None if legacy_pure_lan == Some("false") => return Err("旧 net.pure_lan_default=false 不能开启公网，请显式设置 net.mode 和完整服务器配置".to_owned()),
        None => "lan_only".to_owned(),
    };
    if values.contains_key("net.mode") && legacy_pure_lan.is_some() {
        return Err("net.mode 与旧 net.pure_lan_default 不能同时配置".to_owned());
    }
    let server_host = required(&values, "server.host")?;
    let relay_host = values.get("server.relay_host").cloned().unwrap_or_default(); // HOMEDESK: no relay default.
    let console_enabled = values.get("console.enabled").map_or(false, |v| v == "true");
    let console_trusted_path = values.get("console.trusted_path").map_or(false, |v| v == "true");
    let console_effective = console_enabled && (net_mode == "lan_only" || console_trusted_path);
    let config = BuildConfig {
        brand: BrandConfig {
            app_name: required(&values, "brand.app_name")?,
            config_namespace: values.get("brand.config_namespace").cloned()
                .unwrap_or(required(&values, "brand.app_name")?),
            executable_name: required(&values, "brand.executable_name")?,
            package_name: required(&values, "brand.package_name")?,
        },
        net_mode,
        server_host,
        relay_host,
        server_key: required(&values, "server.key")?,
        whitelist_cidr: required(&values, "net.whitelist_cidr")?,
        source_cidr: values.get("net.source_cidr").cloned().unwrap_or_default(),
        console_enabled: console_effective,
        console_url: if console_effective { required(&values, "console.url")? } else { String::new() },
        console_token: if console_effective { required(&values, "console.token")? } else { String::new() },
        console_trusted_path,
    };
    validate_brand(&config.brand)?;
    validate_server_net(&config)?;
    if config.console_enabled {
        let address = config.console_url.strip_prefix("http://").ok_or("console.url 必须为内网 HTTP 地址")?.trim_end_matches('/');
        let (host, port) = address.rsplit_once(':').ok_or("console.url 必须显式设置端口")?;
        let ip: Ipv4Addr = host.parse().map_err(|_| "console.url 必须使用内网 IPv4，不能使用域名")?;
        if !is_rfc1918(ip) || port.parse::<u16>().map_or(true, |v| v == 0) {
            return Err("console.url 地址或端口无效".into());
        }
        if !(32..=256).contains(&config.console_token.len()) || !config.console_token.bytes().all(|c| c.is_ascii_graphic()) || config.console_token.contains("REPLACE_WITH") {
            return Err("console.token 必须为 32 至 256 位有效访问口令".into());
        }
    }
    Ok(config)
}

fn strip_comment(line: &str) -> &str {
    let mut quoted = false;
    let mut escaped = false;
    for (index, character) in line.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        if quoted && character == '\\' {
            escaped = true;
        } else if character == '"' {
            quoted = !quoted;
        } else if character == '#' && !quoted {
            return &line[..index];
        }
    }
    line
}

fn parse_basic_string(value: &str) -> Result<String, String> {
    if value.len() < 2 || !value.starts_with('"') || !value.ends_with('"') {
        return Err("配置值必须是双引号字符串".to_owned());
    }
    let mut decoded = String::new();
    let mut characters = value[1..value.len() - 1].chars();
    while let Some(character) = characters.next() {
        if character != '\\' {
            decoded.push(character);
            continue;
        }
        let Some(escaped) = characters.next() else {
            return Err("字符串以不完整转义结尾".to_owned());
        };
        decoded.push(match escaped {
            '"' => '"',
            '\\' => '\\',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            _ => return Err(format!("不支持的转义：\\{escaped}")),
        });
    }
    Ok(decoded)
}

fn required(values: &HashMap<String, String>, key: &str) -> Result<String, String> {
    values
        .get(key)
        .cloned()
        .ok_or_else(|| format!("缺少 {key}"))
}

fn validate_brand(config: &BrandConfig) -> Result<(), String> {
    let namespace = &config.config_namespace;
    if namespace.is_empty() || namespace.chars().count() > 64 || namespace.trim() != namespace
        || namespace.chars().any(|c| c.is_control() || r#"<>:"/\|?*"#.contains(c)) {
        return Err("brand.config_namespace 必须是合法的独立配置目录名".to_owned());
    }
    if config.app_name.is_empty() || config.app_name.chars().count() > 64 {
        return Err("brand.app_name 必须为 1 到 64 个字符".to_owned());
    }
    if config.app_name.chars().any(char::is_control) {
        return Err("brand.app_name 不能包含控制字符".to_owned());
    }
    if config.app_name.trim() != config.app_name
        || config
            .app_name
            .chars()
            .any(|character| r#"<>:"/\|?*"#.contains(character))
    {
        return Err("brand.app_name 不能包含文件名保留字符或首尾空白".to_owned());
    }
    for (key, value) in [
        ("executable_name", config.executable_name.as_str()),
        ("package_name", config.package_name.as_str()),
    ] {
        let valid = value.chars().enumerate().all(|(index, character)| {
            character.is_ascii_lowercase()
                || (index > 0 && (character.is_ascii_digit() || character == '-'))
        }) && !value.ends_with('-');
        if value.is_empty() || value.len() > 64 || !valid {
            return Err(format!("brand.{key} 必须为小写 kebab-case 名称"));
        }
    }
    Ok(())
}

fn is_rfc1918(ip: Ipv4Addr) -> bool {
    let [a, b, _, _] = ip.octets();
    a == 10 || (a == 172 && (16..=31).contains(&b)) || (a == 192 && b == 168)
}

fn private_block(ip: u32) -> Option<u8> {
    let address = Ipv4Addr::from(ip);
    let [a, b, _, _] = address.octets();
    if a == 10 {
        Some(10)
    } else if a == 172 && (16..=31).contains(&b) {
        Some(172)
    } else if a == 192 && b == 168 {
        Some(192)
    } else {
        None
    }
}

fn decode_base64(value: &str) -> Option<Vec<u8>> {
    if value.is_empty() || value.len() % 4 != 0 {
        return None;
    }
    let mut decoded = Vec::with_capacity(value.len() / 4 * 3);
    for (chunk_index, chunk) in value.as_bytes().chunks_exact(4).enumerate() {
        let last_chunk = chunk_index + 1 == value.len() / 4;
        let padding = chunk
            .iter()
            .rev()
            .take_while(|character| **character == b'=')
            .count();
        if padding > 2 || (!last_chunk && padding != 0) {
            return None;
        }
        let mut encoded = [0_u8; 4];
        for (index, character) in chunk.iter().copied().enumerate() {
            encoded[index] = match character {
                b'A'..=b'Z' => character - b'A',
                b'a'..=b'z' => character - b'a' + 26,
                b'0'..=b'9' => character - b'0' + 52,
                b'+' => 62,
                b'/' => 63,
                b'=' if last_chunk && padding > 0 && index >= 4 - padding => 0,
                _ => return None,
            };
        }
        if padding == 1 && encoded[2] & 0b11 != 0 || padding == 2 && encoded[1] & 0b1111 != 0 {
            return None;
        }
        let bits = (u32::from(encoded[0]) << 18)
            | (u32::from(encoded[1]) << 12)
            | (u32::from(encoded[2]) << 6)
            | u32::from(encoded[3]);
        decoded.push((bits >> 16) as u8);
        if padding < 2 {
            decoded.push((bits >> 8) as u8);
        }
        if padding == 0 {
            decoded.push(bits as u8);
        }
    }
    Some(decoded)
}

fn validate_server_net(config: &BuildConfig) -> Result<(), String> {
    // HOMEDESK: Generic releases are safely unconfigured; a partial profile is invalid.
    if !config.relay_host.is_empty() { return Err("远控固定 P2P，server.relay_host 必须为空".into()); }
    if config.server_host.is_empty() && config.server_key.is_empty()
        && config.whitelist_cidr.is_empty() && config.source_cidr.is_empty() { return Ok(()); }
    let mode = config.net_mode.as_str();
    if !valid_endpoint(&config.server_host, mode == "self_hosted") {
        return Err(if mode == "lan_only" { "lan_only 的 server.host 必须是 RFC1918 IPv4 地址（可带端口）" } else { "self_hosted 的 server.host 必须是有效公网/私网 IPv4 或域名（可带端口）" }.to_owned());
    }

    if decode_base64(&config.server_key).map_or(true, |key| key.len() != 32) {
        return Err("server.key 必须是解码后 32 字节的 hbbs Base64 公钥".to_owned());
    }

    let (address, prefix) = config
        .whitelist_cidr
        .split_once('/')
        .ok_or_else(|| "net.whitelist_cidr 必须是 IPv4 CIDR".to_owned())?;
    let address: Ipv4Addr = address
        .parse()
        .map_err(|_| "net.whitelist_cidr 必须是 IPv4 CIDR".to_owned())?;
    let prefix: u32 = prefix
        .parse()
        .map_err(|_| "net.whitelist_cidr 前缀无效".to_owned())?;
    if prefix > 32 {
        return Err("net.whitelist_cidr 前缀必须为 0 到 32".to_owned());
    }
    let mask = if prefix == 0 {
        0
    } else {
        u32::MAX << (32 - prefix)
    };
    let network = u32::from(address) & mask;
    let broadcast = network | !mask;
    if private_block(network).is_none() || private_block(network) != private_block(broadcast) {
        return Err("net.whitelist_cidr 必须完全位于同一个 RFC1918 内网范围".to_owned());
    }
    if !config.source_cidr.is_empty() {
        let (address, prefix) = config.source_cidr.split_once('/').ok_or("net.source_cidr 必须是 IPv4 CIDR")?;
        let address: Ipv4Addr = address.parse().map_err(|_| "net.source_cidr 必须是 IPv4 CIDR")?;
        let prefix: u32 = prefix.parse().map_err(|_| "net.source_cidr 前缀无效")?;
        if prefix == 0 || prefix > 32 || address.is_unspecified() || address.is_loopback() || address.is_link_local() || address.is_multicast() {
            return Err("net.source_cidr 地址范围无效或过宽".to_owned());
        }
    }
    Ok(())
}

fn valid_endpoint(value: &str, allow_domain_or_public: bool) -> bool {
    let (host, port) = value.rsplit_once(':').map_or((value, None), |(host, port)| (host, Some(port)));
    if port.map_or(false, |port| port.parse::<u16>().map_or(true, |port| port == 0)) { return false; }
    if let Ok(ip) = host.parse::<Ipv4Addr>() {
        let [a, b, _, _] = ip.octets();
        return !ip.is_unspecified() && !ip.is_loopback() && !ip.is_link_local() && !ip.is_multicast()
            && ip != Ipv4Addr::BROADCAST && a < 240 && !(a == 100 && (64..=127).contains(&b)) && (allow_domain_or_public || is_rfc1918(ip));
    }
    allow_domain_or_public && host.contains('.')
        && !host.bytes().all(|c| c.is_ascii_digit() || c == b'.')
        && !host.rsplit('.').next().map_or(true, |label| label.bytes().all(|c| c.is_ascii_digit()))
        && host.split('.').all(|label| !label.is_empty() && !label.starts_with('-') && !label.ends_with('-') && label.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-'))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renamed_brand_preserves_only_valid_explicit_namespace() {
        let content = VALID_CONFIG.replace("app_name = \"HomeDesk\"",
            "app_name = \"HomeDesk\"\nconfig_namespace = \"HomeDeskAcceptance\"");
        let config = parse_config(&content).unwrap();
        assert_eq!(config.brand.app_name, "HomeDesk");
        assert_eq!(config.brand.config_namespace, "HomeDeskAcceptance");
        assert!(parse_config(&content.replace("HomeDeskAcceptance", "../old")).is_err());
        assert_eq!(parse_config(VALID_CONFIG).unwrap().brand.config_namespace, "HomeDesk");
    }

    const VALID_CONFIG: &str = r#"
        [brand]
        app_name = "HomeDesk"
        executable_name = "homedesk"
        package_name = "homedesk"

        [server]
        host = "192.168.50.10"
        relay_host = ""
        key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

        [net]
        mode = "lan_only"
        whitelist_cidr = "192.168.50.0/24"
    "#;

    #[test]
    fn parses_private_network_defaults() {
        let config = parse_config(VALID_CONFIG).unwrap();
        assert_eq!("192.168.50.10", config.server_host);
        assert_eq!("192.168.50.0/24", config.whitelist_cidr);
        assert_eq!("lan_only", config.net_mode);
        assert!(config.relay_host.is_empty());
    }

    #[test]
    fn rejects_public_server() {
        let content = VALID_CONFIG.replace("192.168.50.10", "8.8.8.8");
        assert!(parse_config(&content).is_err());
    }

    #[test]
    fn rejects_whitelist_that_reaches_public_addresses() {
        let content = VALID_CONFIG.replace("192.168.50.0/24", "192.168.0.0/8");
        assert!(parse_config(&content).is_err());
    }

    #[test]
    fn accepts_explicit_self_hosted_and_rejects_legacy_false() {
        let content = VALID_CONFIG
            .replace("mode = \"lan_only\"", "mode = \"self_hosted\"")
            .replace("192.168.50.10", "remote.example.com");
        assert!(parse_config(&content).is_ok());
        let legacy = VALID_CONFIG.replace("mode = \"lan_only\"", "pure_lan_default = false");
        assert!(parse_config(&legacy).is_err());
    }

    #[test]
    fn self_hosted_rejects_numeric_domain_bypasses_and_bad_sources() {
        let base = VALID_CONFIG.replace("mode = \"lan_only\"", "mode = \"self_hosted\"");
        for value in ["127.1", "127.0.1", "100.64.0.1", "999.999.999.999", "01.2.3.4", "240.0.0.1"] {
            assert!(parse_config(&base.replace("192.168.50.10", value)).is_err(), "{value}");
        }
        for value in ["garbage", "0.0.0.0/0", "127.0.0.0/8"] {
            assert!(parse_config(&base.replace("whitelist_cidr = \"192.168.50.0/24\"", &format!("whitelist_cidr = \"192.168.50.0/24\"\nsource_cidr = \"{value}\""))).is_err(), "{value}");
        }
    }

    #[test]
    fn migrates_legacy_true_and_rejects_mode_conflict() {
        let legacy = VALID_CONFIG.replace("mode = \"lan_only\"", "pure_lan_default = true");
        assert_eq!("lan_only", parse_config(&legacy).unwrap().net_mode);
        let conflict = VALID_CONFIG.replace("mode = \"lan_only\"", "mode = \"lan_only\"\npure_lan_default = true");
        assert!(parse_config(&conflict).is_err());
    }

    #[test]
    fn rejects_malformed_public_key() {
        let invalid_character = VALID_CONFIG.replace(
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA!=",
        );
        let invalid_padding = VALID_CONFIG.replace(
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
        );
        assert!(parse_config(&invalid_character).is_err());
        assert!(parse_config(&invalid_padding).is_err());
    }

    #[test]
    fn rejects_unsafe_executable_name() {
        let content = VALID_CONFIG.replace(
            "executable_name = \"homedesk\"",
            "executable_name = \"../../home\"",
        );
        assert!(parse_config(&content).is_err());
    }

    #[test]
    fn console_disabled_has_no_embedded_credentials() {
        let config=parse_config(&format!("{VALID_CONFIG}\n[console]\nenabled = false\nurl = \"placeholder\"\ntoken = \"placeholder\"\n")).unwrap();
        assert!(!config.console_enabled);
        assert!(config.console_token.is_empty());
        assert!(config.console_url.is_empty());
    }

    #[test]
    fn console_rejects_public_hosts_and_unsafe_tokens() {
        let valid=format!("{VALID_CONFIG}\n[console]\nenabled = true\nurl = \"http://192.168.50.10:8080\"\ntoken = \"test-only-token-00000000000000000000\"\n");
        assert!(parse_config(&valid).is_ok());
        assert!(parse_config(&valid.replace("http://192.168.50.10:8080","http://example.com:8080")).is_err());
        assert!(parse_config(&valid.replace("test-only-token-00000000000000000000","short")).is_err());
    }

    #[test]
    fn self_hosted_console_token_requires_explicit_trusted_path() {
        let public = VALID_CONFIG.replace("mode = \"lan_only\"", "mode = \"self_hosted\"");
        let configured = format!("{public}\n[console]\nenabled = true\nurl = \"http://192.168.50.10:8080\"\ntoken = \"test-only-token-00000000000000000000\"\n");
        let disabled = parse_config(&configured).unwrap();
        assert!(!disabled.console_enabled);
        assert!(disabled.console_token.is_empty());
        let trusted = parse_config(&configured.replace("enabled = true", "enabled = true\ntrusted_path = true")).unwrap();
        assert!(trusted.console_enabled);
        assert!(!trusted.console_token.is_empty());
    }
}
