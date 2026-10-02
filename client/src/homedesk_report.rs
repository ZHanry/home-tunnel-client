// HOMEDESK: 有界、异步的心跳和会话事件发送器，不阻塞远控线程。
use hbb_common::{log, tokio};
use serde_json::Value;
use std::{sync::Arc, time::Duration};
use tokio::sync::mpsc;

pub struct Reporter {
    pub sender: mpsc::Sender<Value>,
    cancel: tokio::sync::watch::Sender<bool>,
}

impl Drop for Reporter {
    fn drop(&mut self) {
        let _ = self.cancel.send(true);
    }
}

pub fn retry_seconds(failures: usize) -> u64 {
    match failures {
        0 => 30,
        1 => 60,
        _ => 300,
    }
}

pub fn start(
    url: String,
    token: String,
    heartbeat: Arc<dyn Fn() -> Option<Value> + Send + Sync>,
) -> Option<Reporter> {
    if url.is_empty() || token.is_empty() {
        return None;
    }
    let client = match reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(5))
        .build()
    {
        Ok(client) => client,
        Err(_) => {
            log::debug!("HomeDesk 上报客户端初始化失败");
            return None;
        }
    };
    let (tx, mut rx) = mpsc::channel::<Value>(256);
    let (cancel, mut cancelled) = tokio::sync::watch::channel(false);
    tokio::spawn(async move {
        let url = url.trim_end_matches('/');
        let mut failures = 0;
        let mut event_failures = 0;
        let mut pending = None;
        loop {
            if *cancelled.borrow() { return; }
            // 每轮先心跳，确保首次会话事件到达前已有设备记录。
            let callback = heartbeat.clone();
            let payload = tokio::select! {
                biased;
                _ = cancelled.changed() => return,
                value = tokio::task::spawn_blocking(move || callback()) => value.ok().flatten(),
            };
            if *cancelled.borrow() { return; }
            let ok = if let Some(payload) = payload {
                tokio::select! {
                    biased;
                    _ = cancelled.changed() => return,
                    response = client
                    .post(format!("{url}/api/v1/heartbeat"))
                    .bearer_auth(&token)
                    .json(&payload)
                    .send()
                    => response.map_or(false, |r| r.status().is_success()),
                }
            } else {
                false
            };
            if !ok {
                log::debug!("HomeDesk 心跳未送达，稍后重试");
                tokio::select! {
                    biased;
                    _ = cancelled.changed() => return,
                    _ = tokio::time::sleep(Duration::from_secs(retry_seconds(failures))) => {}
                }
                failures = failures.saturating_add(1);
                continue;
            }
            failures = 0;
            let deadline = tokio::time::Instant::now() + Duration::from_secs(60);
            loop {
                let event = match pending.take() {
                    Some(event) => event,
                    None => tokio::select! {
                        biased;
                        _ = cancelled.changed() => return,
                        value = tokio::time::timeout_at(deadline, rx.recv()) => match value {
                            Ok(Some(event)) => event,
                            Ok(None) => return,
                            Err(_) => break,
                        }
                    },
                };
                if *cancelled.borrow() { return; }
                let response = tokio::select! {
                    biased;
                    _ = cancelled.changed() => return,
                    response = client
                    .post(format!("{url}/api/v1/session"))
                    .bearer_auth(&token)
                    .json(&event)
                    .send()
                    => response,
                };
                match response {
                    Ok(r) if r.status().is_success() => {
                        event_failures = 0;
                    }
                    Ok(r)
                        if r.status().is_client_error()
                            && r.status().as_u16() != 409
                            && r.status().as_u16() != 429
                            && r.status().as_u16() != 401 =>
                    {
                        log::debug!("HomeDesk 会话事件被拒绝，跳过无效事件");
                    }
                    _ => {
                        pending = Some(event);
                        log::debug!("HomeDesk 会话事件未送达，稍后重试");
                        tokio::select! {
                            biased;
                            _ = cancelled.changed() => return,
                            _ = tokio::time::sleep(Duration::from_secs(retry_seconds(event_failures))) => {}
                        }
                        event_failures = event_failures.saturating_add(1);
                        break;
                    }
                }
                if tokio::time::Instant::now() >= deadline {
                    break;
                }
            }
        }
    });
    Some(Reporter { sender: tx, cancel })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn backoff_is_bounded() {
        assert_eq!(
            [retry_seconds(0), retry_seconds(1), retry_seconds(9)],
            [30, 60, 300]
        );
    }
    #[test]
    fn empty_configuration_starts_no_runtime_or_worker() {
        assert!(start(String::new(), String::new(), Arc::new(|| None)).is_none());
    }
}
