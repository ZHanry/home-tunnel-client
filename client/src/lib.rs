mod keyboard;
mod homedesk_brand; // HOMEDESK: Isolate the compiled application-name default from upstream code.
mod homedesk_async; // HOMEDESK: 异步配置任务的可测试截止时间策略。
mod homedesk_config; // HOMEDESK: 隔离家庭内网服务器、公钥与白名单默认值。
mod nestlink_auth;
mod nestlink_browser;
mod homedesk_tunnel_runtime; // HOMEDESK: 同目录受管隧道助手、账号隔离和许可撤销。
mod homedesk_connection_path; // HOMEDESK: 会话连接路径的被动展示分类。
mod homedesk_net; // HOMEDESK: 独立、可测试的 RFC1918 网络边界。
#[cfg(windows)]
mod homedesk_process; // HOMEDESK: 辅助进程按本应用真实目录限定，避免全机同名误伤。
mod homedesk_report; // HOMEDESK: 有界异步上报传输。
mod homedesk_console; // HOMEDESK: 设备心跳和成功认证会话生命周期。
/// cbindgen:ignore
pub mod platform;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub use platform::{
    clip_cursor, get_cursor, get_cursor_data, get_cursor_pos, get_focused_display,
    set_cursor_pos, start_os_service,
};
#[cfg(not(any(target_os = "ios")))]
/// cbindgen:ignore
mod server;
#[cfg(not(any(target_os = "ios")))]
pub use self::server::*;
mod client;
mod lan;
#[cfg(not(any(target_os = "ios")))]
mod rendezvous_mediator;
#[cfg(not(any(target_os = "ios")))]
pub use self::rendezvous_mediator::*;
/// cbindgen:ignore
pub mod common;
#[cfg(not(any(target_os = "ios")))]
pub mod ipc;
#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    feature = "flutter"
)))]
pub mod ui;
mod version;
pub use version::*;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
mod bridge_generated;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
pub mod flutter;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
pub mod flutter_ffi;
use common::*;
#[cfg(not(target_os = "ios"))]
mod clipboard;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub mod core_main;
mod custom_server;
mod lang;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod port_forward;

#[cfg(all(feature = "flutter", feature = "plugin_framework"))]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub mod plugin;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod tray;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod whiteboard;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod updater;

mod ui_cm_interface;
mod ui_interface;
mod ui_session_interface;

mod hbbs_http;

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub mod clipboard_file;

pub mod privacy_mode;

#[cfg(windows)]
pub mod virtual_display_manager;

mod kcp_stream;
