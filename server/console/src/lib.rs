use askama::Template;
use axum::{
    extract::{ConnectInfo, DefaultBodyLimit, Path, Query, Request, State},
    http::{header, HeaderMap, HeaderValue, StatusCode},
    middleware::{self, Next},
    response::{Html, IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    net::{IpAddr, Ipv4Addr, SocketAddr},
    sync::{Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};
use subtle::ConstantTimeEq;

pub type ApiResult<T> = Result<T, ApiError>;
pub struct ApiError(StatusCode, &'static str);
impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.0, Json(json!({"error":self.1}))).into_response()
    }
}
impl From<rusqlite::Error> for ApiError {
    fn from(e: rusqlite::Error) -> Self {
        eprintln!("数据库操作失败：{e}");
        Self(StatusCode::INTERNAL_SERVER_ERROR, "数据库操作失败")
    }
}
fn bad(message: &'static str) -> ApiError {
    ApiError(StatusCode::BAD_REQUEST, message)
}
pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}
fn digest(token: &str) -> String {
    format!("{:x}", Sha256::digest(token.as_bytes()))
}
fn text_ok(s: &str, max: usize) -> bool {
    !s.chars().any(char::is_control) && s.chars().count() <= max
}
fn id_ok(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 128
        && s.bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"-_.".contains(&c))
}
fn token_ok(s: &str) -> bool {
    (32..=256).contains(&s.len())
        && s.bytes().all(|c| c.is_ascii_graphic())
        && !s.contains("REPLACE_WITH")
}

#[derive(Clone, Copy)]
pub struct Network {
    base: u32,
    mask: u32,
}
impl Network {
    pub fn parse(s: &str) -> ApiResult<Self> {
        let (ip, prefix) = s
            .split_once('/')
            .ok_or_else(|| bad("网段必须为 IPv4 CIDR"))?;
        let ip: Ipv4Addr = ip.parse().map_err(|_| bad("网段地址无效"))?;
        let prefix: u32 = prefix.parse().map_err(|_| bad("网段前缀无效"))?;
        if !(8..=30).contains(&prefix) {
            return Err(bad("网段前缀应为 8 至 30"));
        }
        let mask = u32::MAX << (32 - prefix);
        let base = u32::from(ip) & mask;
        let n = Self { base, mask };
        let start = Ipv4Addr::from(base);
        let end = n.broadcast();
        if !start.is_private() || !end.is_private() || start.octets()[0] != end.octets()[0] {
            return Err(bad("仅允许完整的 RFC1918 内网网段"));
        }
        Ok(n)
    }
    pub fn contains(self, ip: IpAddr) -> bool {
        match ip {
            IpAddr::V4(ip) => u32::from(ip) & self.mask == self.base,
            _ => false,
        }
    }
    pub fn broadcast(self) -> Ipv4Addr {
        Ipv4Addr::from(self.base | !self.mask)
    }
}

#[derive(Clone)]
pub struct AppState {
    db: Arc<Mutex<Connection>>,
    sessions: Arc<Mutex<HashMap<String, i64>>>,
    login_attempts: Arc<Mutex<HashMap<IpAddr, (i64, u32)>>>,
    wol_sent: Arc<Mutex<HashMap<String, i64>>>,
}
impl AppState {
    pub fn open(path: &str, token: &str, cidr: &str, retention: i64) -> ApiResult<Self> {
        if !token_ok(token) {
            return Err(bad("TOKEN 必须为 32 至 256 位且不能使用占位值"));
        }
        Network::parse(cidr)?;
        if !(1..=3650).contains(&retention) {
            return Err(bad("日志保留天数应为 1 至 3650"));
        }
        let db = Connection::open(path)?;
        db.busy_timeout(std::time::Duration::from_secs(3))?;
        db.execute_batch(include_str!("schema.sql"))?;
        for (key, value) in [
            ("token_hash", digest(token)),
            ("net_cidr", cidr.into()),
            ("retention_days", retention.to_string()),
        ] {
            db.execute(
                "INSERT OR IGNORE INTO setting(key,value) VALUES(?1,?2)",
                params![key, value],
            )?;
        }
        let state = Self {
            db: Arc::new(Mutex::new(db)),
            sessions: Default::default(),
            login_attempts: Default::default(),
            wol_sent: Default::default(),
        };
        Network::parse(&state.setting("net_cidr")?)?;
        Ok(state)
    }
    fn setting(&self, key: &str) -> ApiResult<String> {
        Ok(self.db.lock().unwrap().query_row(
            "SELECT value FROM setting WHERE key=?1",
            [key],
            |r| r.get(0),
        )?)
    }
    fn valid_token(&self, token: &str) -> bool {
        self.setting("token_hash").map_or(false, |v| {
            bool::from(v.as_bytes().ct_eq(digest(token).as_bytes()))
        })
    }
    fn network(&self) -> ApiResult<Network> {
        Network::parse(&self.setting("net_cidr")?)
    }
    pub fn cleanup(&self) -> ApiResult<usize> {
        let days: i64 = self
            .setting("retention_days")?
            .parse()
            .map_err(|_| bad("日志保留设置无效"))?;
        Ok(self.db.lock().unwrap().execute(
            "DELETE FROM session_log WHERE at < ?1",
            [now() - days * 86400],
        )?)
    }
}

pub fn app(state: AppState) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/login", post(login))
        .route("/logout", post(logout))
        .route("/app.js", get(js))
        .route("/app.css", get(css))
        .route("/api/v1/heartbeat", post(heartbeat))
        .route("/api/v1/session", post(session))
        .route("/api/v1/devices", get(devices))
        .route("/api/v1/devices/{id}", post(edit_device))
        .route("/api/v1/wol", post(wol))
        .route("/api/v1/sessions", get(sessions))
        .route("/api/v1/sessions.csv", get(export_sessions))
        .route("/api/v1/settings", get(settings).post(save_settings))
        .route_layer(middleware::from_fn_with_state(state.clone(), guard))
        .layer(DefaultBodyLimit::max(16 * 1024))
        .with_state(state)
}
fn cookie(headers: &HeaderMap) -> Option<&str> {
    headers
        .get(header::COOKIE)?
        .to_str()
        .ok()?
        .split(';')
        .find_map(|v| v.trim().strip_prefix("homedesk_session="))
}
async fn guard(State(s): State<AppState>, req: Request, next: Next) -> Response {
    let remote = req
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|v| v.0.ip());
    if remote.map_or(true, |ip| {
        !ip.is_loopback() && !s.network().map_or(false, |n| n.contains(ip))
    }) {
        return ApiError(StatusCode::FORBIDDEN, "当前地址不在家庭网段内").into_response();
    }
    let path = req.uri().path();
    let public = matches!(path, "/" | "/login" | "/app.js" | "/app.css");
    let bearer = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .map_or(false, |t| s.valid_token(t));
    let mut authenticated = bearer;
    if !authenticated {
        let mut sessions = s.sessions.lock().unwrap();
        sessions.retain(|_, expiry| *expiry > now());
        authenticated = cookie(req.headers()).map_or(false, |c| sessions.contains_key(c));
    }
    if !public && !authenticated {
        return ApiError(StatusCode::UNAUTHORIZED, "请先登录管理台").into_response();
    }
    // Cookie 写请求必须由本站脚本发送；Bearer 供客户端使用，浏览器跨站无法无预检添加它。
    if req.method() != "GET"
        && !bearer
        && req
            .headers()
            .get("x-homedesk-request")
            .and_then(|v| v.to_str().ok())
            != Some("1")
    {
        return ApiError(StatusCode::FORBIDDEN, "请求来源无效，请刷新管理台").into_response();
    }
    let mut response = next.run(req).await;
    for (k,v) in [("cache-control","no-store"),("x-content-type-options","nosniff"),("referrer-policy","no-referrer"),("content-security-policy","default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")] {
        response.headers_mut().insert(k,HeaderValue::from_static(v));
    }
    response
}
#[derive(Template)]
#[template(path = "index.html")]
struct Page;
async fn index() -> ApiResult<Html<String>> {
    Ok(Html(Page.render().map_err(|_| {
        ApiError(StatusCode::INTERNAL_SERVER_ERROR, "页面生成失败")
    })?))
}
async fn js() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/javascript; charset=utf-8")],
        include_str!("../static/app.js"),
    )
}
async fn css() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/css; charset=utf-8")],
        include_str!("../static/app.css"),
    )
}
#[derive(Deserialize)]
struct Login {
    token: String,
}
async fn login(
    State(s): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(body): Json<Login>,
) -> ApiResult<Response> {
    {
        let mut attempts = s.login_attempts.lock().unwrap();
        attempts.retain(|_, (at, _)| now() - *at < 60);
        if attempts.len() >= 4096 && !attempts.contains_key(&addr.ip()) {
            return Err(ApiError(StatusCode::TOO_MANY_REQUESTS, "请稍后重试"));
        }
        let item = attempts.entry(addr.ip()).or_insert((now(), 0));
        item.1 += 1;
        if item.1 > 10 {
            return Err(ApiError(
                StatusCode::TOO_MANY_REQUESTS,
                "尝试过于频繁，一分钟后重试",
            ));
        }
    }
    if !s.valid_token(&body.token) {
        return Err(ApiError(StatusCode::UNAUTHORIZED, "访问口令错误"));
    }
    let id = uuid::Uuid::new_v4().to_string();
    {
        let mut sessions = s.sessions.lock().unwrap();
        sessions.retain(|_, e| *e > now());
        if sessions.len() >= 1024 {
            return Err(ApiError(StatusCode::TOO_MANY_REQUESTS, "登录会话过多"));
        }
        sessions.insert(id.clone(), now() + 28800);
    }
    let mut response = Json(json!({"ok":true})).into_response();
    response.headers_mut().insert(
        header::SET_COOKIE,
        HeaderValue::from_str(&format!(
            "homedesk_session={id}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800"
        ))
        .map_err(|_| bad("登录失败"))?,
    );
    Ok(response)
}
async fn logout(State(s): State<AppState>, headers: HeaderMap) -> impl IntoResponse {
    if let Some(id) = cookie(&headers) {
        s.sessions.lock().unwrap().remove(id);
    }
    (
        [(
            header::SET_COOKIE,
            "homedesk_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0",
        )],
        Json(json!({"ok":true})),
    )
}

#[derive(Deserialize, Serialize)]
pub struct Heartbeat {
    pub id: String,
    pub hostname: String,
    pub platform: String,
    pub arch: String,
    pub version: String,
    pub ip: String,
    #[serde(default)]
    pub mac: String,
}
async fn heartbeat(State(s): State<AppState>, Json(b): Json<Heartbeat>) -> ApiResult<Json<Value>> {
    if !id_ok(&b.id)
        || !text_ok(&b.hostname, 128)
        || !text_ok(&b.platform, 32)
        || !text_ok(&b.arch, 32)
        || !text_ok(&b.version, 64)
    {
        return Err(bad("设备信息无效"));
    }
    let ip: IpAddr = b.ip.parse().map_err(|_| bad("设备 IP 无效"))?;
    if !s.network()?.contains(ip) {
        return Err(bad("设备 IP 不在家庭网段内"));
    }
    if !b.mac.is_empty() {
        parse_mac(&b.mac)?;
    }
    let db = s.db.lock().unwrap();
    db.execute("INSERT INTO device(id,name,hostname,platform,arch,version,ip_last,mac,online_at,created_at) VALUES(?1,?2,?2,?3,?4,?5,?6,?7,?8,?8) ON CONFLICT(id) DO UPDATE SET hostname=excluded.hostname,platform=excluded.platform,arch=excluded.arch,version=excluded.version,ip_last=excluded.ip_last,mac=excluded.mac,online_at=excluded.online_at",params![b.id,b.hostname,b.platform,b.arch,b.version,b.ip,b.mac,now()])?;
    Ok(Json(json!({"ok":true})))
}
#[derive(Serialize)]
struct Device {
    id: String,
    name: String,
    hostname: String,
    platform: String,
    arch: String,
    version: String,
    ip_last: String,
    mac: String,
    room: String,
    owner: String,
    online_at: i64,
    online: bool,
    wol_configured: bool,
    wol_mac: String,
}
async fn devices(State(s): State<AppState>) -> ApiResult<Json<Vec<Device>>> {
    let db = s.db.lock().unwrap();
    let mut stmt=db.prepare("SELECT d.id,name,hostname,platform,arch,version,ip_last,d.mac,room,owner,online_at,EXISTS(SELECT 1 FROM wol_target w WHERE w.device_id=d.id),COALESCE((SELECT mac FROM wol_target w WHERE w.device_id=d.id),'') FROM device d ORDER BY room,name,id")?;
    let rows = stmt
        .query_map([], |r| {
            Ok(Device {
                id: r.get(0)?,
                name: r.get(1)?,
                hostname: r.get(2)?,
                platform: r.get(3)?,
                arch: r.get(4)?,
                version: r.get(5)?,
                ip_last: r.get(6)?,
                mac: r.get(7)?,
                room: r.get(8)?,
                owner: r.get(9)?,
                online_at: r.get(10)?,
                online: now() - r.get::<_, i64>(10)? <= 90,
                wol_configured: r.get(11)?,
                wol_mac: r.get(12)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(rows))
}
#[derive(Deserialize)]
struct EditDevice {
    name: String,
    #[serde(default)]
    room: String,
    #[serde(default)]
    owner: String,
    #[serde(default)]
    wol_mac: String,
}
async fn edit_device(
    State(s): State<AppState>,
    Path(id): Path<String>,
    Json(b): Json<EditDevice>,
) -> ApiResult<Json<Value>> {
    if !id_ok(&id)
        || b.name.trim().is_empty()
        || !text_ok(&b.name, 128)
        || !text_ok(&b.room, 64)
        || !text_ok(&b.owner, 64)
    {
        return Err(bad("名称、房间或成员信息无效"));
    }
    if !b.wol_mac.is_empty() {
        parse_mac(&b.wol_mac)?;
    }
    let broadcast = s.network()?.broadcast().to_string();
    let mut db = s.db.lock().unwrap();
    let tx = db.transaction()?;
    if tx.execute(
        "UPDATE device SET name=?1,room=?2,owner=?3 WHERE id=?4",
        params![b.name, b.room, b.owner, id],
    )? == 0
    {
        return Err(ApiError(StatusCode::NOT_FOUND, "设备不存在"));
    }
    if b.wol_mac.is_empty() {
        tx.execute("DELETE FROM wol_target WHERE device_id=?1", [&id])?;
    } else {
        tx.execute("INSERT INTO wol_target(device_id,mac,broadcast_ip,port) VALUES(?1,?2,?3,9) ON CONFLICT(device_id) DO UPDATE SET mac=excluded.mac,broadcast_ip=excluded.broadcast_ip",params![id,b.wol_mac,broadcast])?;
    }
    tx.commit()?;
    Ok(Json(json!({"ok":true})))
}
pub fn parse_mac(s: &str) -> ApiResult<[u8; 6]> {
    let pieces: Vec<_> = s.split([':', '-']).collect();
    if pieces.len() != 6 {
        return Err(bad("MAC 地址无效"));
    }
    let mut mac = [0u8; 6];
    for (i, v) in pieces.iter().enumerate() {
        if v.len() != 2 {
            return Err(bad("MAC 地址无效"));
        }
        mac[i] = u8::from_str_radix(v, 16).map_err(|_| bad("MAC 地址无效"))?;
    }
    if mac == [0; 6] || mac[0] & 1 != 0 {
        return Err(bad("MAC 必须是网卡单播地址"));
    }
    Ok(mac)
}
pub fn magic_packet(mac: [u8; 6]) -> [u8; 102] {
    let mut packet = [255u8; 102];
    for block in packet[6..].chunks_exact_mut(6) {
        block.copy_from_slice(&mac);
    }
    packet
}
#[derive(Deserialize)]
struct Wol {
    device_id: String,
}
async fn wol(State(s): State<AppState>, Json(b): Json<Wol>) -> ApiResult<Json<Value>> {
    let network = s.network()?;
    let (mac, broadcast, port): (String, String, u16) =
        s.db.lock()
            .unwrap()
            .query_row(
                "SELECT mac,broadcast_ip,port FROM wol_target WHERE device_id=?1",
                [&b.device_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?
            .ok_or(ApiError(
                StatusCode::NOT_FOUND,
                "请先编辑设备并配置 WOL 网卡地址",
            ))?;
    if broadcast != network.broadcast().to_string() || port != 9 {
        return Err(bad("WOL 目标不属于当前家庭网段，请重新保存设备设置"));
    }
    let packet = magic_packet(parse_mac(&mac)?);
    {
        let mut sent = s.wol_sent.lock().unwrap();
        sent.retain(|_, at| now() - *at < 30);
        if sent.contains_key(&b.device_id) {
            return Err(ApiError(
                StatusCode::TOO_MANY_REQUESTS,
                "唤醒已发送，请等待 30 秒",
            ));
        }
        if sent.len() >= 4096 {
            return Err(ApiError(StatusCode::TOO_MANY_REQUESTS, "唤醒请求过多"));
        }
        sent.insert(b.device_id.clone(), now());
    }
    let socket = tokio::net::UdpSocket::bind("0.0.0.0:0")
        .await
        .map_err(|_| ApiError(StatusCode::SERVICE_UNAVAILABLE, "无法创建唤醒连接"))?;
    socket
        .set_broadcast(true)
        .map_err(|_| ApiError(StatusCode::SERVICE_UNAVAILABLE, "无法发送广播"))?;
    socket
        .send_to(&packet, (network.broadcast(), port))
        .await
        .map_err(|_| ApiError(StatusCode::SERVICE_UNAVAILABLE, "唤醒发送失败，请检查网络"))?;
    Ok(Json(json!({"ok":true,"message":"已发送，等待设备上线"})))
}

#[derive(Deserialize, Serialize)]
pub struct SessionEvent {
    pub event_id: String,
    pub device_id: String,
    pub peer_id: String,
    pub peer_ip: String,
    pub action: String,
    #[serde(default)]
    pub duration_s: Option<i64>,
    #[serde(default)]
    pub conn_type: String,
}
async fn session(State(s): State<AppState>, Json(b): Json<SessionEvent>) -> ApiResult<Json<Value>> {
    if !id_ok(&b.event_id)
        || !id_ok(&b.device_id)
        || !id_ok(&b.peer_id)
        || !matches!(b.action.as_str(), "start" | "end")
        || !matches!(b.conn_type.as_str(), "" | "direct" | "relay")
        || b.duration_s.map_or(false, |v| v < 0)
    {
        return Err(bad("会话字段无效"));
    }
    if b.peer_ip.parse::<IpAddr>().is_err() {
        return Err(bad("对端 IP 无效"));
    }
    let db = s.db.lock().unwrap();
    if !db.query_row(
        "SELECT EXISTS(SELECT 1 FROM device WHERE id=?1)",
        [&b.device_id],
        |r| r.get::<_, bool>(0),
    )? {
        return Err(ApiError(StatusCode::CONFLICT, "请先上报设备心跳"));
    }
    db.execute("INSERT OR IGNORE INTO session_log(event_id,device_id,peer_id,peer_ip,action,at,duration_s,conn_type) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)",params![b.event_id,b.device_id,b.peer_id,b.peer_ip,b.action,now(),b.duration_s,b.conn_type])?;
    Ok(Json(json!({"ok":true})))
}
#[derive(Deserialize, Default)]
struct SessionFilter {
    device_id: Option<String>,
    from: Option<i64>,
    to: Option<i64>,
    before: Option<i64>,
    limit: Option<u32>,
}
#[derive(Serialize)]
struct SessionRow {
    seq: i64,
    device_id: String,
    peer_id: String,
    peer_ip: String,
    action: String,
    at: i64,
    duration_s: Option<i64>,
    conn_type: String,
}
fn read_sessions(s: &AppState, q: SessionFilter) -> ApiResult<Vec<SessionRow>> {
    if q.from.zip(q.to).map_or(false, |(a, b)| a > b) {
        return Err(bad("开始日期不能晚于结束日期"));
    }
    let db = s.db.lock().unwrap();
    let mut stmt=db.prepare("SELECT seq,device_id,peer_id,peer_ip,action,at,duration_s,conn_type FROM session_log WHERE (?1 IS NULL OR device_id=?1) AND (?2 IS NULL OR at>=?2) AND (?3 IS NULL OR at<=?3) AND (?4 IS NULL OR seq<?4) ORDER BY seq DESC LIMIT ?5")?;
    let result = stmt
        .query_map(
            params![
                q.device_id,
                q.from,
                q.to,
                q.before,
                q.limit.unwrap_or(100).clamp(1, 10000)
            ],
            |r| {
                Ok(SessionRow {
                    seq: r.get(0)?,
                    device_id: r.get(1)?,
                    peer_id: r.get(2)?,
                    peer_ip: r.get(3)?,
                    action: r.get(4)?,
                    at: r.get(5)?,
                    duration_s: r.get(6)?,
                    conn_type: r.get(7)?,
                })
            },
        )?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(result)
}
async fn sessions(
    State(s): State<AppState>,
    Query(q): Query<SessionFilter>,
) -> ApiResult<Json<Vec<SessionRow>>> {
    Ok(Json(read_sessions(&s, q)?))
}
fn csv(s: &str) -> String {
    let prefix = if s.starts_with(['=', '+', '-', '@', '\t', '\r']) {
        "'"
    } else {
        ""
    };
    format!("\"{prefix}{}\"", s.replace('"', "\"\""))
}
async fn export_sessions(
    State(s): State<AppState>,
    Query(q): Query<SessionFilter>,
) -> ApiResult<Response> {
    let mut data = "\u{feff}序号,设备,对端设备,对端地址,事件,时间戳,时长秒,连接方式\r\n".to_owned();
    for r in read_sessions(&s, q)? {
        data.push_str(
            &[
                r.seq.to_string(),
                csv(&r.device_id),
                csv(&r.peer_id),
                csv(&r.peer_ip),
                csv(&r.action),
                r.at.to_string(),
                r.duration_s.map_or(String::new(), |v| v.to_string()),
                csv(&r.conn_type),
            ]
            .join(","),
        );
        data.push_str("\r\n");
    }
    Ok((
        [
            (header::CONTENT_TYPE, "text/csv; charset=utf-8"),
            (
                header::CONTENT_DISPOSITION,
                "attachment; filename=sessions.csv",
            ),
        ],
        data,
    )
        .into_response())
}
async fn settings(State(s): State<AppState>) -> ApiResult<Json<Value>> {
    Ok(Json(
        json!({"net_cidr":s.setting("net_cidr")?,"retention_days":s.setting("retention_days")?.parse::<i64>().unwrap_or(90)}),
    ))
}
#[derive(Deserialize)]
struct Settings {
    net_cidr: String,
    retention_days: i64,
    #[serde(default)]
    new_token: Option<String>,
}
async fn save_settings(
    State(s): State<AppState>,
    Json(b): Json<Settings>,
) -> ApiResult<Json<Value>> {
    let network = Network::parse(&b.net_cidr)?;
    if !(1..=3650).contains(&b.retention_days)
        || b.new_token.as_ref().map_or(false, |v| !token_ok(v))
    {
        return Err(bad("保留天数或新口令无效"));
    }
    {
        let mut db = s.db.lock().unwrap();
        let tx = db.transaction()?;
        for (k, v) in [
            ("net_cidr", b.net_cidr),
            ("retention_days", b.retention_days.to_string()),
        ] {
            tx.execute("UPDATE setting SET value=?1 WHERE key=?2", params![v, k])?;
        }
        tx.execute(
            "UPDATE wol_target SET broadcast_ip=?1",
            [network.broadcast().to_string()],
        )?;
        if let Some(token) = &b.new_token {
            tx.execute(
                "UPDATE setting SET value=?1 WHERE key='token_hash'",
                [digest(token)],
            )?;
        }
        tx.commit()?;
    }
    if b.new_token.is_some() {
        s.sessions.lock().unwrap().clear();
    }
    s.cleanup()?;
    Ok(Json(
        json!({"ok":true,"reauthenticate":b.new_token.is_some()}),
    ))
}
