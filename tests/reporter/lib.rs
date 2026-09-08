// 直接编译生产发送器，仅重导出其所用的运行时，避免加载编解码依赖。
extern crate self as hbb_common;
pub use log;
pub use tokio;
#[path = "../../client/src/homedesk_report.rs"]
pub mod report;

#[cfg(test)]
mod integration {
    use super::*;
    use axum::{routing::post, Json, Router};
    use serde_json::{json, Value};
    use std::sync::{Arc, Mutex};
    #[tokio::test]
    async fn heartbeat_precedes_session_and_sends_bearer() {
        let events = Arc::new(Mutex::new(Vec::<String>::new()));
        let hb = events.clone();
        let audit = events.clone();
        let app = Router::new()
            .route(
                "/api/v1/heartbeat",
                post(
                    move |headers: axum::http::HeaderMap, Json(b): Json<Value>| {
                        let events = hb.clone();
                        async move {
                            assert_eq!(headers["authorization"], "Bearer test-token");
                            assert_eq!(b["id"], "123456");
                            events.lock().unwrap().push("heartbeat".into());
                            Json(json!({"ok":true}))
                        }
                    },
                ),
            )
            .route(
                "/api/v1/session",
                post(move |Json(b): Json<Value>| {
                    let events = audit.clone();
                    async move {
                        events
                            .lock()
                            .unwrap()
                            .push(b["action"].as_str().unwrap().into());
                        Json(json!({"ok":true}))
                    }
                }),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let tx = report::start(
            format!("http://{address}"),
            "test-token".into(),
            Arc::new(|| Some(json!({"id":"123456"}))),
        )
        .unwrap();
        tx.try_send(json!({"action":"start"})).unwrap();
        tx.try_send(json!({"action":"end"})).unwrap();
        tokio::time::timeout(std::time::Duration::from_secs(4), async {
            loop {
                if events.lock().unwrap().len() >= 3 {
                    break;
                }
                tokio::time::sleep(std::time::Duration::from_millis(20)).await;
            }
        })
        .await
        .unwrap();
        assert_eq!(*events.lock().unwrap(), vec!["heartbeat", "start", "end"]);
        drop(tx);
        server.abort();
    }
    #[tokio::test]
    async fn offline_queue_is_bounded_without_blocking_caller() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        drop(listener);
        let tx = report::start(
            format!("http://{address}"),
            "test-token".into(),
            Arc::new(|| None),
        )
        .unwrap();
        for _ in 0..256 {
            assert!(tx.try_send(json!({})).is_ok());
        }
        assert!(tx.try_send(json!({})).is_err());
    }
}
