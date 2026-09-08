use homedesk_console::{app, AppState};
use std::{
    env,
    net::{IpAddr, SocketAddr},
    time::Duration,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let ip: IpAddr = env::var("BIND_IP")
        .unwrap_or_else(|_| "127.0.0.1".into())
        .parse()?;
    if !ip.is_loopback() && !matches!(ip,IpAddr::V4(v) if v.is_private()) {
        return Err("BIND_IP 必须为回环或 RFC1918 内网地址".into());
    }
    let port: u16 = env::var("PORT").unwrap_or_else(|_| "8080".into()).parse()?;
    let token = env::var("TOKEN").map_err(|_| "缺少 TOKEN")?;
    let cidr = env::var("NET_CIDR").map_err(|_| "缺少 NET_CIDR")?;
    let days: i64 = env::var("RETENTION_DAYS")
        .unwrap_or_else(|_| "90".into())
        .parse()?;
    let path = env::var("DB_PATH").unwrap_or_else(|_| "homedesk.sqlite3".into());
    let state =
        AppState::open(&path, &token, &cidr, days).map_err(|_| "管理台配置或数据库初始化失败")?;
    let cleanup = state.clone();
    tokio::spawn(async move {
        loop {
            if cleanup.cleanup().is_err() {
                eprintln!("审计清理失败");
            }
            tokio::time::sleep(Duration::from_secs(86400)).await;
        }
    });
    let listener = tokio::net::TcpListener::bind(SocketAddr::new(ip, port)).await?;
    eprintln!("家庭设备管理台已启动，端口 {port}");
    axum::serve(
        listener,
        app(state).into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(async {
        let _ = tokio::signal::ctrl_c().await;
    })
    .await?;
    Ok(())
}
