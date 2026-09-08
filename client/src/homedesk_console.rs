// HOMEDESK: 上报生命周期与上游服务、连接生命周期隔离。
use hbb_common::{config::Config, log, tokio};
use serde_json::{json, Value};
use std::{
    sync::{Arc, OnceLock},
    time::Instant,
};

static SENDER: OnceLock<tokio::sync::mpsc::Sender<Value>> = OnceLock::new();
pub fn start() {
    if option_env!("HOMEDESK_CONSOLE_ENABLED") != Some("true") || SENDER.get().is_some() {
        return;
    }
    let url = option_env!("HOMEDESK_CONSOLE_URL")
        .unwrap_or_default()
        .to_owned();
    let token = option_env!("HOMEDESK_CONSOLE_TOKEN")
        .unwrap_or_default()
        .to_owned();
    if let Some(tx) = crate::homedesk_report::start(url, token, Arc::new(heartbeat)) {
        let _ = SENDER.set(tx);
    }
}
fn heartbeat() -> Option<Value> {
    let id = Config::get_id();
    if id.is_empty() {
        return None;
    }
    // UDP connect 仅选择本地路由，不发送数据，也不进行域名解析。
    let socket = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    socket
        .connect((crate::homedesk_config::compiled_server(), 21116))
        .ok()?;
    let ip = socket.local_addr().ok()?.ip().to_string();
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let mac = mac_address::get_mac_address()
        .ok()
        .flatten()
        .map(|m| m.to_string())
        .unwrap_or_default();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let mac = String::new();
    Some(
        json!({"id":id,"hostname":crate::common::hostname(),"platform":std::env::consts::OS,"arch":std::env::consts::ARCH,"version":crate::VERSION,"ip":ip,"mac":mac}),
    )
}
fn send(payload: Value) {
    if let Some(tx) = SENDER.get() {
        if tx.try_send(payload).is_err() {
            log::debug!("HomeDesk 上报队列已满或关闭，跳过事件");
        }
    }
}
pub struct SessionGuard {
    id: String,
    device_id: String,
    peer_id: String,
    peer_ip: String,
    conn_type: &'static str,
    start: Instant,
}
impl SessionGuard {
    pub fn new(peer_id: &str, peer_ip: &str, relay: bool) -> Option<Self> {
        if SENDER.get().is_none() {
            return None;
        }
        let s = Self {
            id: uuid::Uuid::new_v4().to_string(),
            device_id: Config::get_id(),
            peer_id: peer_id.into(),
            peer_ip: peer_ip.into(),
            conn_type: if relay { "relay" } else { "direct" },
            start: Instant::now(),
        };
        send(s.event("start", None));
        Some(s)
    }
    fn event(&self, action: &str, duration: Option<u64>) -> Value {
        json!({"event_id":format!("{}-{action}",self.id),"device_id":self.device_id,"peer_id":self.peer_id,"peer_ip":self.peer_ip,"action":action,"duration_s":duration,"conn_type":self.conn_type})
    }
}
impl Drop for SessionGuard {
    fn drop(&mut self) {
        send(self.event("end", Some(self.start.elapsed().as_secs())));
    }
}
