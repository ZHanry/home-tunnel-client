use axum::{
    body::Body,
    extract::ConnectInfo,
    http::{Request, StatusCode},
};
use homedesk_console::{app, magic_packet, parse_mac, AppState, Network};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::ServiceExt;
const TOKEN: &str = "test-only-token-00000000000000000000";
fn state() -> AppState {
    AppState::open(":memory:", TOKEN, "192.168.50.0/24", 90)
        .ok()
        .unwrap()
}
async fn request(
    s: &AppState,
    path: &str,
    body: Option<Value>,
    auth: bool,
) -> (StatusCode, Vec<u8>) {
    let mut r = Request::builder()
        .method(if body.is_some() { "POST" } else { "GET" })
        .uri(path)
        .header("content-type", "application/json");
    if auth {
        r = r.header("authorization", format!("Bearer {TOKEN}"));
    }
    let mut r = r
        .body(body.map_or(Body::empty(), |v| Body::from(v.to_string())))
        .unwrap();
    r.extensions_mut().insert(ConnectInfo(
        "192.168.50.2:12000"
            .parse::<std::net::SocketAddr>()
            .unwrap(),
    ));
    let response = app(s.clone()).oneshot(r).await.unwrap();
    let status = response.status();
    (
        status,
        response
            .into_body()
            .collect()
            .await
            .unwrap()
            .to_bytes()
            .to_vec(),
    )
}
fn heartbeat() -> Value {
    json!({"id":"123456","hostname":"书房","platform":"Windows","arch":"x86_64","version":"1.4.9","ip":"192.168.50.2","mac":"02:11:22:33:44:55"})
}
fn event() -> Value {
    json!({"event_id":"session-1-start","device_id":"123456","peer_id":"654321","peer_ip":"192.168.50.3","action":"start","conn_type":"direct"})
}
#[tokio::test]
async fn all_apis_require_authentication() {
    let s = state();
    for (path, b) in [
        ("/api/v1/devices", None),
        ("/api/v1/heartbeat", Some(heartbeat())),
        ("/api/v1/session", Some(event())),
        ("/api/v1/wol", Some(json!({"device_id":"123456"}))),
        ("/api/v1/devices/123456", Some(json!({"name":"test"}))),
        ("/api/v1/sessions", None),
        ("/api/v1/sessions.csv", None),
        ("/api/v1/settings", None),
        ("/api/v1/settings", Some(json!({}))),
    ] {
        assert_eq!(
            request(&s, path, b, false).await.0,
            StatusCode::UNAUTHORIZED,
            "{path}"
        );
    }
}
#[tokio::test]
async fn heartbeat_upsert_preserves_room_and_name() {
    let s = state();
    assert_eq!(
        request(&s, "/api/v1/heartbeat", Some(heartbeat()), true)
            .await
            .0,
        StatusCode::OK
    );
    assert_eq!(request(&s,"/api/v1/devices/123456",Some(json!({"name":"爸爸的电脑","room":"书房","owner":"爸爸","wol_mac":"02:11:22:33:44:55"})),true).await.0,StatusCode::OK);
    request(&s, "/api/v1/heartbeat", Some(heartbeat()), true).await;
    let (_, b) = request(&s, "/api/v1/devices", None, true).await;
    let rows: Value = serde_json::from_slice(&b).unwrap();
    assert_eq!(rows.as_array().unwrap().len(), 1);
    assert_eq!(rows[0]["name"], "爸爸的电脑");
    assert_eq!(rows[0]["room"], "书房");
    assert_eq!(rows[0]["online"], true);
    assert_eq!(rows[0]["wol_configured"], true);
}
#[tokio::test]
async fn rejects_bad_payloads_and_unknown_device() {
    let s = state();
    let mut b = heartbeat();
    b["ip"] = json!("8.8.8.8");
    assert_eq!(
        request(&s, "/api/v1/heartbeat", Some(b), true).await.0,
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        request(&s, "/api/v1/session", Some(event()), true).await.0,
        StatusCode::CONFLICT
    );
    assert_eq!(
        request(
            &s,
            "/api/v1/devices/missing",
            Some(json!({"name":"test"})),
            true
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        request(
            &s,
            "/api/v1/wol",
            Some(json!({"device_id":"missing"})),
            true
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
}
#[tokio::test]
async fn audit_is_idempotent_filtered_and_exportable() {
    let s = state();
    request(&s, "/api/v1/heartbeat", Some(heartbeat()), true).await;
    for _ in 0..2 {
        assert_eq!(
            request(&s, "/api/v1/session", Some(event()), true).await.0,
            StatusCode::OK
        );
    }
    let (_, b) = request(&s, "/api/v1/sessions?device_id=123456", None, true).await;
    assert_eq!(
        serde_json::from_slice::<Value>(&b)
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );
    let (_, b) = request(&s, "/api/v1/sessions?device_id=missing", None, true).await;
    assert_eq!(serde_json::from_slice::<Value>(&b).unwrap(), json!([]));
    let (status, b) = request(&s, "/api/v1/sessions.csv", None, true).await;
    assert_eq!(status, StatusCode::OK);
    assert!(String::from_utf8(b).unwrap().contains("123456"));
    let mut bad = event();
    bad["action"] = json!("bogus");
    assert_eq!(
        request(&s, "/api/v1/session", Some(bad), true).await.0,
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        request(&s, "/api/v1/sessions?from=20&to=10", None, true)
            .await
            .0,
        StatusCode::BAD_REQUEST
    );
}
#[tokio::test]
async fn settings_validation_and_token_rotation() {
    let s = state();
    let old = json!({"net_cidr":"0.0.0.0/0","retention_days":90});
    assert_eq!(
        request(&s, "/api/v1/settings", Some(old), true).await.0,
        StatusCode::BAD_REQUEST
    );
    let valid = json!({"net_cidr":"192.168.50.0/24","retention_days":30});
    assert_eq!(
        request(&s, "/api/v1/settings", Some(valid), true).await.0,
        StatusCode::OK
    );
    let (_, b) = request(&s, "/api/v1/settings", None, true).await;
    let value: Value = serde_json::from_slice(&b).unwrap();
    assert_eq!(value["retention_days"], 30);
    assert!(value.get("token_hash").is_none());
    let change = json!({"net_cidr":"192.168.50.0/24","retention_days":30,"new_token":"replacement-test-token-00000000000000"});
    assert_eq!(
        request(&s, "/api/v1/settings", Some(change), true).await.0,
        StatusCode::OK
    );
    assert_eq!(
        request(&s, "/api/v1/devices", None, true).await.0,
        StatusCode::UNAUTHORIZED
    );
}
#[tokio::test]
async fn login_cookie_csrf_logout_and_source_boundary() {
    let s = state();
    let mut r = Request::builder()
        .method("POST")
        .uri("/login")
        .header("content-type", "application/json")
        .header("x-homedesk-request", "1")
        .body(Body::from(json!({"token":TOKEN}).to_string()))
        .unwrap();
    r.extensions_mut().insert(ConnectInfo(
        "192.168.50.2:1234".parse::<std::net::SocketAddr>().unwrap(),
    ));
    let resp = app(s.clone()).oneshot(r).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let cookie = resp.headers()["set-cookie"].to_str().unwrap().to_owned();
    assert!(cookie.contains("HttpOnly"));
    let pair = cookie.split(';').next().unwrap();
    for (path, header, status) in [
        ("/api/v1/settings", false, StatusCode::FORBIDDEN),
        ("/logout", true, StatusCode::OK),
    ] {
        let mut r = Request::builder()
            .method("POST")
            .uri(path)
            .header("cookie", pair)
            .header("content-type", "application/json");
        if header {
            r = r.header("x-homedesk-request", "1");
        }
        let mut r = r.body(Body::from("{}")).unwrap();
        r.extensions_mut().insert(ConnectInfo(
            "192.168.50.2:1234".parse::<std::net::SocketAddr>().unwrap(),
        ));
        assert_eq!(app(s.clone()).oneshot(r).await.unwrap().status(), status);
    }
    let mut r = Request::builder().uri("/").body(Body::empty()).unwrap();
    r.extensions_mut().insert(ConnectInfo(
        "8.8.8.8:1234".parse::<std::net::SocketAddr>().unwrap(),
    ));
    assert_eq!(
        app(s).oneshot(r).await.unwrap().status(),
        StatusCode::FORBIDDEN
    );
}
#[tokio::test]
async fn pages_and_assets_are_embedded() {
    let s = state();
    for path in ["/", "/app.js", "/app.css"] {
        let (status, b) = request(&s, path, None, false).await;
        assert_eq!(status, StatusCode::OK);
        assert!(!b.is_empty());
    }
}
#[test]
fn wol_packet_and_network_boundary() {
    let mac = parse_mac("02:11:22:33:44:55").ok().unwrap();
    let packet = magic_packet(mac);
    assert_eq!(&packet[..6], &[255; 6]);
    for chunk in packet[6..].chunks_exact(6) {
        assert_eq!(chunk, &mac);
    }
    assert!(parse_mac("ff:ff:ff:ff:ff:ff").is_err());
    assert!(parse_mac("00:00:00:00:00:00").is_err());
    assert!(Network::parse("172.16.0.0/8").is_err());
    assert_eq!(
        Network::parse("192.168.50.0/24")
            .ok()
            .unwrap()
            .broadcast()
            .to_string(),
        "192.168.50.255"
    );
}

#[tokio::test]
async fn wol_target_survives_heartbeat_and_database_restart() {
    let path = std::env::temp_dir().join(format!("homedesk-test-{}.sqlite3", uuid::Uuid::new_v4()));
    let s = AppState::open(path.to_str().unwrap(), TOKEN, "192.168.50.0/24", 90)
        .ok()
        .unwrap();
    request(&s, "/api/v1/heartbeat", Some(heartbeat()), true).await;
    request(
        &s,
        "/api/v1/devices/123456",
        Some(json!({"name":"书房","room":"楼上","wol_mac":"02:aa:bb:cc:dd:ee"})),
        true,
    )
    .await;
    let mut updated = heartbeat();
    updated["mac"] = json!("");
    request(&s, "/api/v1/heartbeat", Some(updated), true).await;
    request(&s, "/api/v1/session", Some(event()), true).await;
    drop(s);
    let s = AppState::open(path.to_str().unwrap(), TOKEN, "192.168.50.0/24", 90)
        .ok()
        .unwrap();
    let (_, body) = request(&s, "/api/v1/devices", None, true).await;
    let rows: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(rows[0]["wol_mac"], "02:aa:bb:cc:dd:ee");
    assert_eq!(rows[0]["mac"], "");
    assert_eq!(rows[0]["room"], "楼上");
    {
        let db = rusqlite::Connection::open(&path).unwrap();
        db.execute("UPDATE device SET online_at=0", []).unwrap();
        db.execute("UPDATE session_log SET at=0", []).unwrap();
    }
    assert_eq!(s.cleanup().ok().unwrap(), 1);
    let (_, body) = request(&s, "/api/v1/devices", None, true).await;
    let rows: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(rows[0]["online"], false);
    drop(s);
    std::fs::remove_file(path).unwrap();
}
