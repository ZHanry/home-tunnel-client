// 直接编译生产发送器，仅重导出其所用的运行时，避免加载编解码依赖。
extern crate self as hbb_common;
pub use log;
pub use tokio;
#[path = "../../client/src/homedesk_report.rs"]
pub mod report;

#[cfg(test)]
mod integration {
    use super::*;
    use axum::{http::StatusCode, routing::post, Json, Router};
    use serde_json::{json, Value};
    use std::sync::{mpsc, Arc, Mutex};
    use tokio::sync::{oneshot, Notify};
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
        let reporter = report::start(
            format!("http://{address}"),
            "test-token".into(),
            Arc::new(|| Some(json!({"id":"123456"}))),
        )
        .unwrap();
        reporter.sender.try_send(json!({"action":"start"})).unwrap();
        reporter.sender.try_send(json!({"action":"end"})).unwrap();
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
        drop(reporter);
        server.abort();
    }
    #[tokio::test]
    async fn offline_queue_is_bounded_without_blocking_caller() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        drop(listener);
        let reporter = report::start(
            format!("http://{address}"),
            "test-token".into(),
            Arc::new(|| None),
        )
        .unwrap();
        for _ in 0..256 {
            assert!(reporter.sender.try_send(json!({})).is_ok());
        }
        assert!(reporter.sender.try_send(json!({})).is_err());
    }

    #[tokio::test]
    async fn dropping_reporter_cancels_inflight_http_and_discards_queued_events() {
        let heartbeat_started = Arc::new(Notify::new());
        let release_heartbeat = Arc::new(Notify::new());
        let session_seen = Arc::new(Notify::new());
        let session_requests = Arc::new(Mutex::new(0usize));
        let app = Router::new()
            .route(
                "/api/v1/heartbeat",
                post({
                    let heartbeat_started = heartbeat_started.clone();
                    let release_heartbeat = release_heartbeat.clone();
                    move |headers: axum::http::HeaderMap| {
                        let heartbeat_started = heartbeat_started.clone();
                        let release_heartbeat = release_heartbeat.clone();
                        async move {
                            assert_eq!(headers["authorization"], "Bearer test-token");
                            heartbeat_started.notify_one();
                            release_heartbeat.notified().await;
                            Json(json!({"ok":true}))
                        }
                    }
                }),
            )
            .route(
                "/api/v1/session",
                post({
                    let session_seen = session_seen.clone();
                    let session_requests = session_requests.clone();
                    move || {
                        let session_seen = session_seen.clone();
                        let session_requests = session_requests.clone();
                        async move {
                            *session_requests.lock().unwrap() += 1;
                            session_seen.notify_one();
                            Json(json!({"ok":true}))
                        }
                    }
                }),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let reporter = report::start(
            format!("http://{address}"),
            "test-token".into(),
            Arc::new(|| Some(json!({"id":"123456"}))),
        )
        .unwrap();
        let sender = reporter.sender.clone();
        tokio::time::timeout(
            std::time::Duration::from_secs(1),
            heartbeat_started.notified(),
        )
        .await
        .unwrap();
        sender.try_send(json!({"action":"start"})).unwrap();
        drop(reporter);
        tokio::time::timeout(std::time::Duration::from_millis(250), sender.closed())
            .await
            .expect("取消应中断进行中的 HTTP 请求并结束消费者");
        release_heartbeat.notify_waiters();
        assert_eq!(*session_requests.lock().unwrap(), 0);
        assert!(tokio::time::timeout(
            std::time::Duration::from_millis(150),
            session_seen.notified()
        )
        .await
        .is_err());
        server.abort();
    }

    #[tokio::test]
    async fn dropping_reporter_cancels_failure_backoff_without_retry() {
        let first_request = Arc::new(Notify::new());
        let requests = Arc::new(Mutex::new(0usize));
        let app = Router::new().route(
            "/api/v1/heartbeat",
            post({
                let first_request = first_request.clone();
                let requests = requests.clone();
                move || {
                    let first_request = first_request.clone();
                    let requests = requests.clone();
                    async move {
                        *requests.lock().unwrap() += 1;
                        first_request.notify_one();
                        StatusCode::INTERNAL_SERVER_ERROR
                    }
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let reporter = report::start(
            format!("http://{address}"),
            "test-token".into(),
            Arc::new(|| Some(json!({"id":"123456"}))),
        )
        .unwrap();
        let sender = reporter.sender.clone();
        tokio::time::timeout(std::time::Duration::from_secs(1), first_request.notified())
            .await
            .unwrap();
        drop(reporter);
        tokio::time::timeout(std::time::Duration::from_millis(250), sender.closed())
            .await
            .expect("取消不能等待 30 秒退避");
        assert_eq!(*requests.lock().unwrap(), 1);
        server.abort();
    }

    #[tokio::test]
    async fn dropping_reporter_while_heartbeat_callback_blocks_sends_no_request() {
        let (callback_started, callback_started_rx) = oneshot::channel();
        let (release_callback, release_callback_rx) = mpsc::sync_channel::<()>(0);
        let callback_started = Arc::new(Mutex::new(Some(callback_started)));
        let release_callback_rx = Arc::new(Mutex::new(release_callback_rx));
        let request_seen = Arc::new(Notify::new());
        let app = Router::new().route(
            "/api/v1/heartbeat",
            post({
                let request_seen = request_seen.clone();
                move || {
                    let request_seen = request_seen.clone();
                    async move {
                        request_seen.notify_one();
                        Json(json!({"ok":true}))
                    }
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let reporter = report::start(
            format!("http://{address}"),
            "test-token".into(),
            Arc::new(move || {
                callback_started
                    .lock()
                    .unwrap()
                    .take()
                    .unwrap()
                    .send(())
                    .unwrap();
                release_callback_rx.lock().unwrap().recv().unwrap();
                Some(json!({"id":"123456"}))
            }),
        )
        .unwrap();
        let sender = reporter.sender.clone();
        tokio::time::timeout(std::time::Duration::from_secs(1), callback_started_rx)
            .await
            .unwrap()
            .unwrap();
        drop(reporter);
        tokio::time::timeout(std::time::Duration::from_millis(250), sender.closed())
            .await
            .expect("取消应在阻塞采样回调完成前结束消费者");
        release_callback.send(()).unwrap();
        assert!(tokio::time::timeout(
            std::time::Duration::from_millis(150),
            request_seen.notified()
        )
        .await
        .is_err());
        server.abort();
    }
}
