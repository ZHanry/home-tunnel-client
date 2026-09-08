// HOMEDESK: 纯函数形式定义家庭内网边界，可脱离完整 RustDesk 依赖单测。
use std::net::Ipv4Addr;

pub fn is_private_rendezvous_server(server: &str) -> bool {
    let host = server
        .trim()
        .rsplit_once(':')
        .map_or(server.trim(), |(host, port)| {
            if port.parse::<u16>().map_or(false, |port| port > 0) {
                host
            } else {
                server.trim()
            }
        });
    let Ok(address) = host.parse::<Ipv4Addr>() else {
        return false;
    };
    let [a, b, _, _] = address.octets();
    a == 10 || (a == 172 && (16..=31).contains(&b)) || (a == 192 && b == 168)
}

pub fn is_private_whitelist(value: &str) -> bool {
    normalize_private_whitelist(value).is_some()
}

pub fn normalize_private_whitelist(value: &str) -> Option<String> {
    let items: Vec<&str> = value
        .split(|separator: char| separator == ',' || separator == ';' || separator.is_whitespace())
        .filter(|item| !item.is_empty())
        .collect();
    if items.is_empty() {
        return None;
    }
    let valid = items.iter().all(|item| {
        let (address, prefix) = item
            .trim()
            .split_once('/')
            .map_or((item.trim(), "32"), |value| value);
        let Ok(address) = address.parse::<Ipv4Addr>() else {
            return false;
        };
        let Ok(prefix) = prefix.parse::<u32>() else {
            return false;
        };
        if prefix > 32 {
            return false;
        }
        let mask = if prefix == 0 {
            0
        } else {
            u32::MAX << (32 - prefix)
        };
        let network = u32::from(address) & mask;
        let broadcast = network | !mask;
        private_block(network).is_some() && private_block(network) == private_block(broadcast)
    });
    valid.then(|| items.join(","))
}

fn private_block(raw_address: u32) -> Option<u8> {
    let [a, b, _, _] = Ipv4Addr::from(raw_address).octets();
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

pub fn address_in_whitelist(address: &str, whitelist: &str) -> bool {
    let address = address.rsplit_once(':').filter(|(_,port)|port.parse::<u16>().map_or(false,|p|p>0)).map_or(address,|(ip,_)|ip);
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
    fn direct_addresses_and_ports_respect_the_family_subnet() {
        assert!(address_in_whitelist("192.168.50.2:21118","192.168.50.0/24"));
        assert!(!address_in_whitelist("192.168.51.2:21118","192.168.50.0/24"));
        assert!(!address_in_whitelist("192.168.50.2:65536","192.168.50.0/24"));
        assert!(!address_in_whitelist("example.com","192.168.50.0/24"));
    }

    #[test]
    fn only_rfc1918_rendezvous_servers_are_accepted() {
        assert!(is_private_rendezvous_server("192.168.50.10"));
        assert!(is_private_rendezvous_server("10.0.0.2:21116"));
        assert!(is_private_rendezvous_server("172.31.1.8:21116"));
        assert!(!is_private_rendezvous_server("10.0.0.2:65536"));
        assert!(!is_private_rendezvous_server("rs-ny.rustdesk.com:21116"));
        assert!(!is_private_rendezvous_server("8.8.8.8:21116"));
        assert!(!is_private_rendezvous_server("172.32.1.8:21116"));
    }

    #[test]
    fn whitelist_cannot_cross_private_network_boundary() {
        assert!(is_private_whitelist("192.168.50.0/24"));
        assert!(is_private_whitelist("10.1.0.0/16,172.16.1.10"));
        assert_eq!(
            normalize_private_whitelist("10.1.0.0/16; 172.16.1.10\n192.168.1.0/24"),
            Some("10.1.0.0/16,172.16.1.10,192.168.1.0/24".to_owned())
        );
        assert!(!is_private_whitelist(""));
        assert!(!is_private_whitelist("  , ;\n"));
        assert!(!is_private_whitelist("0.0.0.0"));
        assert!(!is_private_whitelist("192.168.0.0/8"));
        assert!(!is_private_whitelist("2001:db8::/64"));
    }
}
