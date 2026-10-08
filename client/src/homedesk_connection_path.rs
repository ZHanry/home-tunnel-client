// HOMEDESK: 被动展示连接选择结果；不参与拨号、打洞、路由或加密决策。
use std::net::SocketAddr;
use crate::homedesk_net::{self, NetworkMode};

pub fn classify_manual(peer: &str, family_cidr: &str, transport: &str) -> &'static str {
    let endpoint = peer.parse::<SocketAddr>().ok().or_else(||
        peer.parse::<std::net::IpAddr>().ok().map(|ip| SocketAddr::new(ip, 1)));
    classify(true, endpoint, true, family_cidr, transport)
}

pub fn classify(direct: bool, endpoint: Option<SocketAddr>, local_hint: bool,
    family_cidr: &str, transport: &str) -> &'static str {
    if !direct { return "relay"; }
    // TCP 选择分支提供的是实际成功候选；可选 UDP/IPv6 缺少同等端点数据时保留未知。
    if transport != "TCP" { return "direct_unknown"; }
    let Some(endpoint) = endpoint else { return "direct_unknown"; };
    let std::net::IpAddr::V4(ip) = endpoint.ip() else { return "direct_unknown"; };
    if homedesk_net::is_rfc1918(ip) {
        if local_hint && homedesk_net::address_in_whitelist(&ip.to_string(), family_cidr) {
            return "lan";
        }
        return "direct_unknown";
    }
    if homedesk_net::is_valid_server(&ip.to_string(), NetworkMode::SelfHosted) {
        "p2p"
    } else { "direct_unknown" }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn route_uses_selected_endpoint_and_relay_result() {
        let family = "192.168.50.0/24";
        let local = Some("192.168.50.20:12345".parse().unwrap());
        assert_eq!(classify(true, local, true, family, "TCP"), "lan");
        assert_eq!(classify(false, local, true, family, "TCP"), "relay");
        assert_eq!(classify(true, Some("203.0.113.20:12345".parse().unwrap()), false, family, "TCP"), "p2p");
        assert_eq!(classify(true, local, false, family, "TCP"), "direct_unknown");
        assert_eq!(classify(true, local, true, family, "UDP"), "direct_unknown");
        assert_eq!(classify(true, Some("127.0.0.1:12345".parse().unwrap()), true, family, "TCP"), "direct_unknown");
        assert_eq!(classify_manual("192.168.50.20", family, "TCP"), "lan");
    }
}
