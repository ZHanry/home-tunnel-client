// HOMEDESK: 上报生命周期与上游服务、连接生命周期隔离。
use hbb_common::{config::Config, log};
use serde_json::{json, Value};
use std::{
    sync::{Arc, Mutex, OnceLock},
    time::Instant,
};

static REPORTER: OnceLock<Mutex<Option<crate::homedesk_report::Reporter>>> = OnceLock::new();
fn reporter() -> &'static Mutex<Option<crate::homedesk_report::Reporter>> {
    REPORTER.get_or_init(|| Mutex::new(None))
}
pub fn start() {
    refresh_policy();
}
pub fn refresh_policy() {
    let mut current = reporter().lock().unwrap();
    if !crate::homedesk_config::console_allowed() {
        current.take(); // HOMEDESK: Drop 立即取消在途/退避中的请求并清空待发送事件。
        return;
    }
    if current.is_some() { return; }
    let url = option_env!("HOMEDESK_CONSOLE_URL")
        .unwrap_or_default()
        .to_owned();
    let token = option_env!("HOMEDESK_CONSOLE_TOKEN")
        .unwrap_or_default()
        .to_owned();
    if let Some(tx) = crate::homedesk_report::start(url, token, Arc::new(heartbeat)) {
        *current = Some(tx);
    }
}
fn heartbeat() -> Option<Value> {
    if !crate::homedesk_config::console_allowed() { return None; }
    let id = Config::get_id();
    if id.is_empty() {
        return None;
    }
    // UDP connect 仅选择到已配置连接服务器的本地路由，不发送数据。
    let socket = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    let configured_server = crate::homedesk_config::active_profile().server;
    let server_host = configured_server.rsplit_once(':').map_or(configured_server.as_str(), |(host, port)| {
        if port.parse::<u16>().map_or(false, |port| port > 0) { host } else { configured_server.as_str() }
    });
    socket
        .connect((server_host, 21116))
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
    if !crate::homedesk_config::console_allowed() { return; }
    if let Some(runtime) = reporter().lock().unwrap().as_ref() {
        if runtime.sender.try_send(payload).is_err() {
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
        if !crate::homedesk_config::console_allowed() || reporter().lock().unwrap().is_none() {
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
