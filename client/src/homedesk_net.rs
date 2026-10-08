// HOMEDESK: 纯函数形式定义两种网络模式的地址边界，可脱离完整 RustDesk 依赖单测。
use std::net::{Ipv4Addr, SocketAddr};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NetworkMode { LanOnly, SelfHosted }

impl NetworkMode {
    pub fn parse(value: &str) -> Option<Self> {
        match value { "lan_only" => Some(Self::LanOnly), "self_hosted" => Some(Self::SelfHosted), _ => None }
    }
    pub const fn as_str(self) -> &'static str {
        match self { Self::LanOnly => "lan_only", Self::SelfHosted => "self_hosted" }
    }
}

fn split_host_port(value: &str) -> Option<(&str, Option<u16>)> {
    let value = value.trim();
    if value.is_empty() || value.contains(['/', '\\', '@', '[', ']']) { return None; }
    if let Some((host, port)) = value.rsplit_once(':') {
        let port = port.parse::<u16>().ok().filter(|port| *port > 0)?;
        if host.is_empty() || host.contains(':') { return None; }
        Some((host, Some(port)))
    } else { Some((value, None)) }
}

fn is_valid_domain(host: &str) -> bool {
    host.len() <= 253 && host.contains('.') && !host.bytes().all(|c| c.is_ascii_digit() || c == b'.')
        && !host.rsplit('.').next().map_or(true, |label| label.bytes().all(|c| c.is_ascii_digit()))
        && host.split('.').all(|label| {
        !label.is_empty() && label.len() <= 63 && !label.starts_with('-') && !label.ends_with('-')
            && label.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
    })
}

fn is_special(ip: Ipv4Addr) -> bool {
    let [a, b, _, _] = ip.octets();
    ip.is_unspecified() || ip.is_loopback() || ip.is_link_local() || ip.is_multicast()
        || ip == Ipv4Addr::BROADCAST || a == 0 || a >= 240 || (a == 100 && (64..=127).contains(&b))
}

fn is_family_network_or_broadcast(address: Ipv4Addr, whitelist: &str) -> bool {
    whitelist.split(|c: char| c == ',' || c == ';' || c.is_whitespace()).any(|entry| {
        let (ip, prefix) = entry.split_once('/').unwrap_or((entry, "32"));
        let (Ok(ip), Ok(prefix)) = (ip.parse::<Ipv4Addr>(), prefix.parse::<u32>()) else { return false; };
        let mask = if prefix == 0 { 0 } else { u32::MAX << (32-prefix) };
        let network = u32::from(ip) & mask;
        let broadcast = network | !mask;
        let raw = u32::from(address);
        prefix < 32 && (raw == network || raw == broadcast)
    })
}

pub fn is_valid_server(server: &str, mode: NetworkMode) -> bool {
    let Some((host, _)) = split_host_port(server) else { return false; };
    if let Ok(ip) = host.parse::<Ipv4Addr>() {
        return !is_special(ip) && (mode == NetworkMode::SelfHosted || is_rfc1918(ip));
    }
    mode == NetworkMode::SelfHosted && is_valid_domain(host)
}

pub fn is_private_rendezvous_server(server: &str) -> bool { is_valid_server(server, NetworkMode::LanOnly) }

// HOMEDESK: Both initiating and receiving sides use this immutable policy.
pub fn relay_allowed(_candidate: &str) -> bool { false }
pub fn remote_request_allowed(force_relay: bool, websocket: bool, proxy: bool) -> bool {
    !force_relay && !websocket && !proxy
}
pub fn direct_session_allowed(direct: bool, secured: bool, verified_peer_key: bool) -> bool {
    direct && secured && verified_peer_key
}

pub fn peer_endpoint_allowed(endpoint: SocketAddr, mode: NetworkMode, is_local: bool, family_cidr: &str) -> bool {
    let SocketAddr::V4(endpoint) = endpoint else { return false; };
    if endpoint.port() == 0 || is_special(*endpoint.ip()) { return false; }
    match mode {
        NetworkMode::LanOnly => address_in_whitelist(&endpoint.ip().to_string(), family_cidr) && !is_family_network_or_broadcast(*endpoint.ip(), family_cidr),
        NetworkMode::SelfHosted if is_rfc1918(*endpoint.ip()) => is_local && address_in_whitelist(&endpoint.ip().to_string(), family_cidr) && !is_family_network_or_broadcast(*endpoint.ip(), family_cidr),
        NetworkMode::SelfHosted => true,
    }
}

pub fn secure_session_allowed(_mode: NetworkMode, is_secured: bool, has_verified_peer_key: bool) -> bool {
    // HOMEDESK: LAN also requires an authenticated encrypted ID session.
    is_secured && has_verified_peer_key
}

pub fn console_allowed(mode: NetworkMode, enabled: bool, trusted_path: bool) -> bool {
    enabled && (mode == NetworkMode::LanOnly || trusted_path)
}

// HOMEDESK: Remote mode/confirmation cannot revoke independently approved tunneling.
pub fn home_tunnel_allowed(_mode: NetworkMode, _profile_confirmed: bool) -> bool {
    true
}

pub fn configured_key_allowed(candidate: &str, configured: &str) -> bool {
    candidate.is_empty() || candidate == configured
}

pub fn is_private_whitelist(value: &str) -> bool { normalize_private_whitelist(value).is_some() }

pub fn normalize_source_whitelist(value: &str) -> Option<String> {
    if value.trim().is_empty() { return Some(String::new()); }
    let items: Vec<&str> = value.split(|c: char| c == ',' || c == ';' || c.is_whitespace()).filter(|item| !item.is_empty()).collect();
    let valid = items.iter().all(|item| {
        let (address, prefix) = item.split_once('/').unwrap_or((item, "32"));
        let (Ok(address), Ok(prefix)) = (address.parse::<Ipv4Addr>(), prefix.parse::<u32>()) else { return false; };
        prefix > 0 && prefix <= 32 && !is_special(address)
    });
    valid.then(|| items.join(","))
}

pub fn source_endpoint_allowed(endpoint: SocketAddr, whitelist: &str) -> bool {
    if whitelist.trim().is_empty() { return true; }
    let SocketAddr::V4(endpoint) = endpoint else { return false; };
    whitelist.split(|c: char| c == ',' || c == ';' || c.is_whitespace()).any(|entry| {
        let (ip, prefix) = entry.split_once('/').unwrap_or((entry, "32"));
        let (Ok(ip), Ok(prefix)) = (ip.parse::<Ipv4Addr>(), prefix.parse::<u32>()) else { return false; };
        let mask = if prefix == 0 { 0 } else { u32::MAX << (32-prefix) };
        u32::from(*endpoint.ip()) & mask == u32::from(ip) & mask
    })
}

pub fn normalize_private_whitelist(value: &str) -> Option<String> {
    let items: Vec<&str> = value.split(|separator: char| separator == ',' || separator == ';' || separator.is_whitespace()).filter(|item| !item.is_empty()).collect();
    if items.is_empty() { return None; }
    let valid = items.iter().all(|item| {
        let (address, prefix) = item.trim().split_once('/').map_or((item.trim(), "32"), |v| v);
        let Ok(address) = address.parse::<Ipv4Addr>() else { return false; };
        let Ok(prefix) = prefix.parse::<u32>() else { return false; };
        if prefix > 32 { return false; }
        let mask = if prefix == 0 { 0 } else { u32::MAX << (32 - prefix) };
        let network = u32::from(address) & mask;
        let broadcast = network | !mask;
        private_block(network).is_some() && private_block(network) == private_block(broadcast)
    });
    valid.then(|| items.join(","))
}

pub(crate) fn is_rfc1918(ip: Ipv4Addr) -> bool { // HOMEDESK: 供被动会话路径展示复用。
    let [a, b, _, _] = ip.octets();
    a == 10 || (a == 172 && (16..=31).contains(&b)) || (a == 192 && b == 168)
}

fn private_block(raw_address: u32) -> Option<u8> {
    let [a, b, _, _] = Ipv4Addr::from(raw_address).octets();
    if a == 10 { Some(10) } else if a == 172 && (16..=31).contains(&b) { Some(172) } else if a == 192 && b == 168 { Some(192) } else { None }
}

pub fn address_in_whitelist(address: &str, whitelist: &str) -> bool {
    let address = address.rsplit_once(':').filter(|(_, port)| port.parse::<u16>().map_or(false, |p| p > 0)).map_or(address, |(ip, _)| ip);
    let Ok(address) = address.parse::<Ipv4Addr>() else { return false; };
    if normalize_private_whitelist(whitelist).is_none() { return false; }
    whitelist.split(|c: char| c == ',' || c == ';' || c.is_whitespace()).any(|entry| {
        let (ip, prefix) = entry.split_once('/').unwrap_or((entry, "32"));
        let (Ok(ip), Ok(prefix)) = (ip.parse::<Ipv4Addr>(), prefix.parse::<u32>()) else { return false; };
        let mask = if prefix == 0 { 0 } else { u32::MAX << (32-prefix) };
        u32::from(address) & mask == u32::from(ip) & mask
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn servers_follow_mode_and_reject_special_addresses() {
        assert!(is_valid_server("192.168.50.10:21116", NetworkMode::LanOnly));
        assert!(!is_valid_server("remote.example.com:21116", NetworkMode::LanOnly));
        assert!(is_valid_server("remote.example.com:21116", NetworkMode::SelfHosted));
        assert!(is_valid_server("203.0.113.9:21116", NetworkMode::SelfHosted));
        for value in ["0.0.0.0:21116", "127.0.0.1:21116", "169.254.1.1:21116", "224.0.0.1:21116", "127.1:21116", "127.0.1:21116", "999.999.999.999:21116", "01.2.3.4:21116", "host:0", "[::1]:21116"] {
            assert!(!is_valid_server(value, NetworkMode::SelfHosted), "{value}");
        }
    }

    #[test]
    fn strict_p2p_rejects_every_override_and_insecure_success() {
        for candidate in ["", "relay.example.com", "192.168.50.10:21117", "203.0.113.1:443"] {
            assert!(!relay_allowed(candidate));
        }
        for force in [false, true] { for websocket in [false, true] { for proxy in [false, true] {
            assert_eq!(remote_request_allowed(force, websocket, proxy), !force && !websocket && !proxy);
        }}}
        for direct in [false, true] { for secured in [false, true] { for verified in [false, true] {
            assert_eq!(direct_session_allowed(direct, secured, verified), direct && secured && verified);
        }}}
    }

    #[test]
    fn peer_candidates_respect_mode_and_local_marker() {
        let public: SocketAddr = "203.0.113.7:42000".parse().unwrap();
        let private: SocketAddr = "192.168.50.7:42000".parse().unwrap();
        assert!(!peer_endpoint_allowed(public, NetworkMode::LanOnly, false, "192.168.50.0/24"));
        assert!(peer_endpoint_allowed(public, NetworkMode::SelfHosted, false, "192.168.50.0/24"));
        assert!(!peer_endpoint_allowed(private, NetworkMode::SelfHosted, false, "192.168.50.0/24"));
        assert!(peer_endpoint_allowed(private, NetworkMode::SelfHosted, true, "192.168.50.0/24"));
        assert!(!peer_endpoint_allowed("192.168.50.0:21118".parse().unwrap(), NetworkMode::LanOnly, true, "192.168.50.0/24"));
        assert!(!peer_endpoint_allowed("192.168.50.255:21118".parse().unwrap(), NetworkMode::LanOnly, true, "192.168.50.0/24"));
        assert!(!peer_endpoint_allowed("240.0.0.1:21118".parse().unwrap(), NetworkMode::SelfHosted, false, "192.168.50.0/24"));
        assert!(!peer_endpoint_allowed("100.64.0.1:21118".parse().unwrap(), NetworkMode::SelfHosted, false, "192.168.50.0/24"));
        assert!(!peer_endpoint_allowed("127.0.0.1:1".parse().unwrap(), NetworkMode::SelfHosted, true, "192.168.50.0/24"));
        assert!(!peer_endpoint_allowed("[::1]:21118".parse().unwrap(), NetworkMode::SelfHosted, true, "192.168.50.0/24"));
    }

    #[test]
    fn self_hosted_rejects_every_insecure_fallback_shape() {
        assert!(!secure_session_allowed(NetworkMode::SelfHosted, false, false));
        assert!(!secure_session_allowed(NetworkMode::SelfHosted, false, true));
        assert!(!secure_session_allowed(NetworkMode::SelfHosted, true, false));
        assert!(secure_session_allowed(NetworkMode::SelfHosted, true, true));
        assert!(!secure_session_allowed(NetworkMode::LanOnly, false, false));
        assert!(!secure_session_allowed(NetworkMode::LanOnly, true, false));
        assert!(secure_session_allowed(NetworkMode::LanOnly, true, true));
    }

    #[test]
    fn console_token_requires_trusted_path_in_self_hosted_mode() {
        assert!(console_allowed(NetworkMode::LanOnly, true, false));
        assert!(!console_allowed(NetworkMode::SelfHosted, true, false));
        assert!(console_allowed(NetworkMode::SelfHosted, true, true));
        assert!(!console_allowed(NetworkMode::LanOnly, false, true));
    }

    #[test]
    fn remote_profile_changes_do_not_revoke_tunneling() {
        assert!(home_tunnel_allowed(NetworkMode::LanOnly, true));
        assert!(home_tunnel_allowed(NetworkMode::LanOnly, false));
        assert!(home_tunnel_allowed(NetworkMode::SelfHosted, false));
        assert!(home_tunnel_allowed(NetworkMode::SelfHosted, true));
    }

    #[test]
    fn same_server_cannot_override_configured_trust_anchor() {
        assert!(configured_key_allowed("", "configured-key"));
        assert!(configured_key_allowed("configured-key", "configured-key"));
        assert!(!configured_key_allowed("other-key", "configured-key"));
    }

    #[test]
    fn whitelist_cannot_cross_private_network_boundary() {
        assert_eq!(normalize_private_whitelist("10.1.0.0/16; 172.16.1.10\n192.168.1.0/24"), Some("10.1.0.0/16,172.16.1.10,192.168.1.0/24".to_owned()));
        assert!(!is_private_whitelist("0.0.0.0"));
        assert!(!is_private_whitelist("192.168.0.0/8"));
        assert!(!is_private_whitelist("2001:db8::/64"));
        assert_eq!(normalize_source_whitelist("203.0.113.0/24;198.51.100.7"), Some("203.0.113.0/24,198.51.100.7".to_owned()));
        assert!(normalize_source_whitelist("").is_some());
        assert!(normalize_source_whitelist("garbage").is_none());
        assert!(normalize_source_whitelist("0.0.0.0/0").is_none());
    }
}
