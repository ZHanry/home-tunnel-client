// HOMEDESK: 隔离读取单仓库构建配置，避免把家庭网络参数散落到上游代码。
use std::{collections::HashMap, env, fs, net::Ipv4Addr, path::PathBuf};

#[derive(Debug, PartialEq)]
struct BrandConfig {
    app_name: String,
    executable_name: String,
    package_name: String,
}

#[derive(Debug, PartialEq)]
struct BuildConfig {
    brand: BrandConfig,
    server_host: String,
    server_key: String,
    whitelist_cidr: String,
    pure_lan_default: bool,
    console_enabled: bool,
    console_url: String,
    console_token: String,
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
    println!(
        "cargo:rustc-env=HOMEDESK_EXECUTABLE_NAME={}",
        config.brand.executable_name
    );
    println!(
        "cargo:rustc-env=HOMEDESK_PACKAGE_NAME={}",
        config.brand.package_name
    );
    println!(
        "cargo:rustc-env=HOMEDESK_SERVER_HOST={}",
        config.server_host
    );
    println!("cargo:rustc-env=HOMEDESK_SERVER_KEY={}", config.server_key);
    println!(
        "cargo:rustc-env=HOMEDESK_WHITELIST_CIDR={}",
        config.whitelist_cidr
    );
    println!(
        "cargo:rustc-env=HOMEDESK_PURE_LAN_DEFAULT={}",
        config.pure_lan_default
    );
    println!("cargo:rustc-env=HOMEDESK_CONSOLE_ENABLED={}", config.console_enabled);
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
        let value = if matches!(full_key.as_str(), "net.pure_lan_default" | "console.enabled") {
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
                | "brand.executable_name"
                | "brand.package_name"
                | "server.host"
                | "server.key"
                | "net.whitelist_cidr"
                | "net.pure_lan_default"
                | "console.enabled"
                | "console.url"
                | "console.token"
        ) {
            return Err(format!("第 {} 行包含未知配置 {full_key}", index + 1));
        }
        if values.insert(full_key.clone(), value).is_some() {
            return Err(format!("第 {} 行重复定义 {full_key}", index + 1));
        }
    }

    let config = BuildConfig {
        brand: BrandConfig {
            app_name: required(&values, "brand.app_name")?,
            executable_name: required(&values, "brand.executable_name")?,
            package_name: required(&values, "brand.package_name")?,
        },
        server_host: required(&values, "server.host")?,
        server_key: required(&values, "server.key")?,
        whitelist_cidr: required(&values, "net.whitelist_cidr")?,
        pure_lan_default: required(&values, "net.pure_lan_default")? == "true",
        console_enabled: values.get("console.enabled").map_or(false, |v| v == "true"),
        console_url: if values.get("console.enabled").map_or(false, |v| v == "true") { required(&values, "console.url")? } else { String::new() },
        console_token: if values.get("console.enabled").map_or(false, |v| v == "true") { required(&values, "console.token")? } else { String::new() },
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
    let host: Ipv4Addr = config
        .server_host
        .parse()
        .map_err(|_| "server.host 必须是 RFC1918 内网 IPv4 地址".to_owned())?;
    if !is_rfc1918(host) {
        return Err("server.host 必须是 RFC1918 内网 IPv4 地址".to_owned());
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
    if !config.pure_lan_default {
        return Err("T-02 阶段要求 net.pure_lan_default = true".to_owned());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID_CONFIG: &str = r#"
        [brand]
        app_name = "HomeDesk"
        executable_name = "homedesk"
        package_name = "homedesk"

        [server]
        host = "192.168.50.10"
        key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

        [net]
        whitelist_cidr = "192.168.50.0/24"
        pure_lan_default = true
    "#;

    #[test]
    fn parses_private_network_defaults() {
        let config = parse_config(VALID_CONFIG).unwrap();
        assert_eq!("192.168.50.10", config.server_host);
        assert_eq!("192.168.50.0/24", config.whitelist_cidr);
        assert!(config.pure_lan_default);
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
    fn rejects_public_network_default() {
        let content = VALID_CONFIG.replace("pure_lan_default = true", "pure_lan_default = false");
        assert!(parse_config(&content).is_err());
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
}
