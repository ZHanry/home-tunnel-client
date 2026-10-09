//! Account authorization for every native remote entry point. Tokens exist only in memory.
use hbb_common::{anyhow::anyhow, bail, base64, config::Config, lazy_static::lazy_static,
    protobuf::UnknownValueRef, sodiumoxide::crypto::sign, tokio, ResultType};
use serde_derive::{Deserialize, Serialize};
use base64::{engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD}, Engine as _};
use std::{fmt, sync::{Arc, RwLock, atomic::{AtomicBool, AtomicU64, Ordering}}, time::{Duration, Instant}};

const PERMIT_FIELD: u32 = 100;
static EPOCH: AtomicU64 = AtomicU64::new(1);
static REVISION: AtomicU64 = AtomicU64::new(1);
static MONITORING: AtomicBool = AtomicBool::new(false);
#[cfg(not(any(target_os = "android", target_os = "ios")))]
static WATCHING: AtomicBool = AtomicBool::new(false);
lazy_static! {
    static ref AUTH: RwLock<Option<ValidatedAuth>> = RwLock::new(None);
    static ref AUTH_CHANGED: tokio::sync::Notify = tokio::sync::Notify::new();
    static ref AUTH_UPDATES: tokio::sync::watch::Sender<u64> = tokio::sync::watch::channel(1).0;
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AuthRequest {
    pub origin: String,
    pub device_id: String,
    pub access_token: String,
}
impl fmt::Debug for AuthRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AuthRequest").field("origin", &self.origin).field("device_id", &self.device_id).finish_non_exhaustive()
    }
}
#[derive(Clone, Deserialize, PartialEq, Eq)]
struct Trust { algorithm: String, public_key: String, realm: String }
#[derive(Clone, Deserialize, PartialEq, Eq)]
struct Presence {
    device_id: String, session_id: String, server: String, key: String, key_sha256: String,
    family_cidr: String, source_cidr: String, permit_trust: Trust,
}
#[derive(Clone)]
struct ValidatedAuth { request: AuthRequest, presence: Presence, valid_until: Instant, revision: u64, epoch: u64 }

fn http_client() -> ResultType<reqwest::Client> {
    let builder = reqwest::Client::builder().https_only(true).no_proxy()
        .redirect(reqwest::redirect::Policy::none()).timeout(Duration::from_secs(5));
    // Mobile OpenSSL does not load the operating-system trust store. Use the same
    // certificate-verifying platform configuration as the existing native HTTP stack.
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let builder = builder.use_preconfigured_tls(hbb_common::verifier::client_config_safe()?);
    Ok(builder.build()?)
}
async fn request(auth: &AuthRequest, method: reqwest::Method, path: &str, body: Option<serde_json::Value>) -> ResultType<serde_json::Value> {
    let mut query = http_client()?.request(method, format!("{}{}", auth.origin, path)).bearer_auth(&auth.access_token);
    if let Some(body) = body { query = query.json(&body); }
    let response = query.send().await?;
    if !response.status().is_success() { bail!("账号或远控许可已失效（HTTP {}）", response.status().as_u16()); }
    if response.status() == reqwest::StatusCode::NO_CONTENT { return Ok(serde_json::Value::Null); }
    let mut response = response;
    if response.content_length().is_some_and(|length| length > 64 * 1024) { bail!("服务返回了超出限制的数据"); }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        if bytes.len() + chunk.len() > 64 * 1024 { bail!("服务返回了超出限制的数据"); }
        bytes.extend_from_slice(&chunk);
    }
    Ok(serde_json::from_slice(&bytes)?)
}

pub fn ready() -> bool {
    AUTH.read().unwrap().as_ref().map_or(false, |auth| Instant::now() < auth.valid_until)
}
pub fn current_request() -> Option<AuthRequest> {
    AUTH.read().unwrap().as_ref().filter(|auth| Instant::now() < auth.valid_until).map(|auth| auth.request.clone())
}
pub fn clear() {
    {
        let mut auth = AUTH.write().unwrap();
        *auth = None;
        REVISION.fetch_add(1, Ordering::SeqCst);
        EPOCH.fetch_add(1, Ordering::SeqCst);
    }
    AUTH_CHANGED.notify_waiters();
    #[cfg(target_os = "android")]
    if let Err(error) = scrap::android::call_main_service_set_by_name("account_revoked", None, None) {
        hbb_common::log::debug!("NestLink capture authorization ended: {error}");
    }
    AUTH_UPDATES.send_replace(REVISION.load(Ordering::SeqCst));
    #[cfg(not(target_os = "ios"))]
    crate::rendezvous_mediator::RendezvousMediator::restart();
}
pub fn subscribe() -> tokio::sync::watch::Receiver<u64> { AUTH_UPDATES.subscribe() }
fn clear_revision(revision: u64) {
    clear_if_revision(revision, true);
}
fn clear_if_revision(revision: u64, require_installed: bool) {
    {
        let mut auth = AUTH.write().unwrap();
        if REVISION.load(Ordering::SeqCst) != revision || (require_installed && auth.as_ref().map(|auth| auth.revision) != Some(revision)) { return; }
        *auth = None;
        REVISION.fetch_add(1, Ordering::SeqCst);
        EPOCH.fetch_add(1, Ordering::SeqCst);
    }
    AUTH_CHANGED.notify_waiters();
    #[cfg(target_os = "android")]
    if let Err(error) = scrap::android::call_main_service_set_by_name("account_revoked", None, None) {
        hbb_common::log::debug!("NestLink capture authorization ended: {error}");
    }
    AUTH_UPDATES.send_replace(REVISION.load(Ordering::SeqCst));
    #[cfg(not(target_os = "ios"))]
    crate::rendezvous_mediator::RendezvousMediator::restart();
}
fn snapshot() -> ResultType<ValidatedAuth> {
    AUTH.read().unwrap().as_ref().filter(|auth| Instant::now() < auth.valid_until).cloned()
        .ok_or_else(|| anyhow!("请先登录自建服务"))
}

pub async fn install(auth: AuthRequest) -> ResultType<()> {
    if crate::homedesk_config::normalize_portal_origin(&auth.origin).as_deref() != Some(auth.origin.as_str())
        || uuid::Uuid::parse_str(&auth.device_id).is_err() || auth.access_token.len() < 32 || auth.access_token.len() > 256 {
        bail!("自建服务登录信息无效");
    }
    let revision = {
        let _current = AUTH.write().unwrap();
        REVISION.fetch_add(1, Ordering::SeqCst) + 1
    };
    let result = request(&auth, reqwest::Method::GET, "/api/v2/remote/presence", None).await
        .and_then(|value| Ok(serde_json::from_value::<Presence>(value)?));
    let presence = match result {
        Ok(presence) => presence,
        Err(error) => {
            clear_if_revision(revision, false);
            return Err(error);
        }
    };
    if presence.device_id != auth.device_id || presence.permit_trust.algorithm != "Ed25519"
        || uuid::Uuid::parse_str(&presence.session_id).is_err()
        || presence.permit_trust.realm.is_empty() || presence.permit_trust.realm.len() > 128
        || STANDARD.decode(&presence.permit_trust.public_key).ok().and_then(|key| sign::PublicKey::from_slice(&key)).is_none() {
        clear_if_revision(revision, false);
        bail!("自建服务没有返回有效的设备授权");
    }
    let mut current = AUTH.write().unwrap();
    if revision != REVISION.load(Ordering::SeqCst) { bail!("账号授权已被更新或退出"); }
    if let Err(error) = crate::homedesk_config::save_network_profile(crate::homedesk_config::NetworkProfile {
        mode: crate::homedesk_net::NetworkMode::SelfHosted, server: presence.server.clone(), relay: String::new(),
        key: presence.key.clone(), family_cidr: presence.family_cidr.clone(), source_cidr: presence.source_cidr.clone(),
    }) {
        drop(current);
        clear_if_revision(revision, false);
        return Err(anyhow!(error));
    }
    crate::homedesk_config::mark_profile_confirmed();
    let changed = current.as_ref().map_or(true, |old| old.request.origin != auth.origin || old.presence != presence);
    let epoch = if changed { EPOCH.fetch_add(1, Ordering::SeqCst) + 1 } else { EPOCH.load(Ordering::SeqCst) };
    *current = Some(ValidatedAuth { request: auth, presence, valid_until: Instant::now() + Duration::from_secs(15), revision, epoch });
    drop(current);
    AUTH_UPDATES.send_replace(revision);
    if changed {
        AUTH_CHANGED.notify_waiters();
        #[cfg(not(target_os = "ios"))]
        crate::rendezvous_mediator::RendezvousMediator::restart();
    }
    if MONITORING.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_ok() {
        tokio::spawn(async {
            let mut timer = tokio::time::interval(Duration::from_secs(5));
            loop {
                timer.tick().await;
                let Ok(auth) = snapshot() else { continue; };
                let result = request(&auth.request, reqwest::Method::GET, "/api/v2/remote/presence", None).await
                    .and_then(|value| Ok(serde_json::from_value::<Presence>(value)?));
                match result {
                    Ok(presence) if presence == auth.presence => {
                        let mut current = AUTH.write().unwrap();
                        if let Some(current) = current.as_mut() {
                            if current.revision == auth.revision { current.valid_until = Instant::now() + Duration::from_secs(15); }
                        }
                    }
                    Ok(_) => clear_revision(auth.revision),
                    Err(error) => {
                        hbb_common::log::warn!("NestLink account authorization ended: {error}");
                        clear_revision(auth.revision);
                    }
                }
            }
        });
    }
    Ok(())
}

pub async fn ensure_current() -> ResultType<()> {
    if ready() { return Ok(()); }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if let Some(auth) = crate::ipc::nestlink_auth_request().await? {
        install(auth).await?;
        start_account_watch();
        return Ok(());
    }
    bail!("请先登录自建服务");
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn start_account_watch() {
    if WATCHING.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() { return; }
    tokio::spawn(async {
        loop {
            let result = async {
                let mut connection = crate::ipc::connect(1500, "").await?;
                connection.send(&crate::ipc::Data::NestLinkAuth { action: "watch".into(), auth: None, error: None }).await?;
                while let Some(data) = connection.next().await? {
                    match data {
                        crate::ipc::Data::NestLinkAuth { auth: Some(auth), error: Some(error), .. } if error.is_empty() => {
                            // The daemon sends each token rotation and logout over this authenticated IPC connection.
                            install(auth).await?;
                        }
                        crate::ipc::Data::NestLinkAuth { auth: None, .. } => clear(),
                        _ => bail!("后台账号授权通知无效"),
                    }
                }
                Ok::<(), hbb_common::anyhow::Error>(())
            }.await;
            if let Err(error) = result { hbb_common::log::debug!("NestLink account subscriber: {error}"); }
            clear();
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    });
}

async fn authorized_request(auth: &ValidatedAuth, method: reqwest::Method, path: &str, body: Option<serde_json::Value>) -> ResultType<serde_json::Value> {
    match request(&auth.request, method.clone(), path, body.clone()).await {
        Ok(value) if auth.epoch == EPOCH.load(Ordering::SeqCst) && ready() => Ok(value),
        Ok(_) => bail!("账号授权已结束"),
        Err(error) => {
            // A refresh can invalidate the old token while the daemon's replacement is still in flight.
            let mut updates = subscribe();
            if REVISION.load(Ordering::SeqCst) != auth.revision && *updates.borrow() == auth.revision {
                let _ = tokio::time::timeout(Duration::from_secs(6), updates.changed()).await;
            }
            let current = snapshot()?;
            if current.epoch != auth.epoch || current.revision == auth.revision { return Err(error); }
            request(&current.request, method, path, body).await
        }
    }
}

#[derive(Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PermitClaims {
    pub v: u32, pub typ: String, pub jti: String, pub realm: String, pub iat: u64, pub exp: u64,
    pub controller_device: String, pub host_device: String,
    pub controller_session: String, pub host_session: String,
    pub controller_id: String, pub host_id: String,
    pub controller_key: String, pub host_key: String, pub policy: String,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Envelope { permit: String, proof: String }

fn now_seconds() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |value| value.as_secs())
}
fn verify_permit(token: &str, trust: &Trust) -> ResultType<PermitClaims> {
    verify_permit_at(token, trust, now_seconds())
}
fn verify_permit_at(token: &str, trust: &Trust, now: u64) -> ResultType<PermitClaims> {
    if token.len() > 4096 { bail!("远控许可超出长度限制"); }
    let parts: Vec<_> = token.split('.').collect();
    if parts.len() != 3 || parts[0] != "nlp2" { bail!("远控许可格式无效"); }
    let signature = sign::Signature::from_bytes(&URL_SAFE_NO_PAD.decode(parts[2])?)
        .map_err(|_| anyhow!("远控许可签名无效"))?;
    let key = sign::PublicKey::from_slice(&STANDARD.decode(&trust.public_key)?).ok_or_else(|| anyhow!("服务公钥无效"))?;
    if !sign::verify_detached(&signature, format!("nlp2.{}", parts[1]).as_bytes(), &key) { bail!("远控许可签名无效"); }
    let claims: PermitClaims = serde_json::from_slice(&URL_SAFE_NO_PAD.decode(parts[1])?)?;
    if claims.v != 2 || claims.typ != "NestLink-P2P" || claims.realm != trust.realm || claims.policy != "require_direct"
        || claims.iat > now.saturating_add(5) || claims.exp <= now || claims.exp.checked_sub(claims.iat) != Some(45)
        || uuid::Uuid::parse_str(&claims.jti).is_err() { bail!("远控许可已过期或属于其他自建服务"); }
    Ok(claims)
}

pub struct SessionGuard { epoch: u64, permit_id: String, alive: Arc<AtomicBool> }
impl SessionGuard {
    pub async fn revoked(&self) {
        loop {
            if !self.alive.load(Ordering::SeqCst) || self.epoch != EPOCH.load(Ordering::SeqCst) || !ready() { return; }
            let _ = tokio::time::timeout(Duration::from_secs(1), AUTH_CHANGED.notified()).await;
        }
    }
    fn start(permit_id: String, epoch: u64) -> Arc<Self> {
        let guard = Arc::new(Self { epoch, permit_id: permit_id.clone(), alive: Arc::new(AtomicBool::new(true)) });
        let alive = guard.alive.clone();
        let epoch = guard.epoch;
        tokio::spawn(async move {
            let mut timer = tokio::time::interval(Duration::from_secs(5));
            while alive.load(Ordering::SeqCst) && epoch == EPOCH.load(Ordering::SeqCst) {
                timer.tick().await;
                let Ok(auth) = snapshot() else { break; };
                if let Err(error) = authorized_request(&auth, reqwest::Method::POST, &format!("/api/v2/remote/permits/{permit_id}/heartbeat"), Some(serde_json::json!({}))).await {
                    hbb_common::log::warn!("NestLink remote permission ended: {error}");
                    break;
                }
            }
            alive.store(false, Ordering::SeqCst);
            AUTH_CHANGED.notify_waiters();
        });
        guard
    }
}
impl Drop for SessionGuard {
    fn drop(&mut self) {
        self.alive.store(false, Ordering::SeqCst);
        let id = self.permit_id.clone();
        let Ok(auth) = snapshot() else { return; };
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async move {
                if let Err(error) = request(&auth.request, reqwest::Method::DELETE, &format!("/api/v2/remote/permits/{id}"), None).await {
                    hbb_common::log::debug!("NestLink remote permission close: {error}");
                }
            });
        }
    }
}

pub struct PreparedPermit { pub envelope: Vec<u8>, pub claims: PermitClaims, pub guard: Arc<SessionGuard> }
async fn key_pair() -> ResultType<(Vec<u8>, Vec<u8>)> {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    { return Ok(Config::get_key_pair()); }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let mut connection = crate::ipc::connect(1500, "").await?;
        connection.send(&crate::ipc::Data::ConfirmedKey(None)).await?;
        match connection.next_timeout(2500).await? {
            Some(crate::ipc::Data::ConfirmedKey(Some(pair))) => Ok(pair),
            _ => bail!("设备身份尚未注册到自建信令服务"),
        }
    }
}
pub async fn binding_proof() -> ResultType<String> {
    let auth = snapshot()?;
    let (secret, public) = key_pair().await?;
    let secret = sign::SecretKey::from_slice(&secret).ok_or_else(|| anyhow!("设备私钥无效"))?;
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let remote_id = Config::get_id();
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let remote_id = crate::ipc::get_config_async("id", 1500).await?
        .filter(|id| !id.is_empty()).ok_or_else(|| anyhow!("后台未返回设备 ID"))?;
    let input = format!("NestLink-binding-v2:{}:{}:{remote_id}", auth.presence.permit_trust.realm, auth.request.device_id);
    Ok(serde_json::json!({ "device_id": auth.request.device_id, "remote_id": remote_id,
        "server": auth.presence.server, "key_sha256": auth.presence.key_sha256,
        "remote_public_key": STANDARD.encode(public), "remote_proof": STANDARD.encode(sign::sign_detached(input.as_bytes(), &secret).to_bytes()) }).to_string())
}
pub async fn prepare(target: &str, connection_id: u64) -> ResultType<PreparedPermit> {
    ensure_current().await?;
    if target.is_empty() || target.len() > 64 || !target.bytes().all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-')) || connection_id == 0 {
        bail!("请使用设备 ID 连接");
    }
    let auth = snapshot()?;
    let reply = authorized_request(&auth, reqwest::Method::POST, "/api/v2/remote/permits", Some(serde_json::json!({ "target_id": target }))).await?;
    let permit = reply["permit"].as_str().ok_or_else(|| anyhow!("服务未返回远控许可"))?;
    let claims = verify_permit(permit, &auth.presence.permit_trust)?;
    if claims.controller_device != auth.request.device_id || claims.controller_session != auth.presence.session_id || claims.host_id != target { bail!("远控许可设备范围无效"); }
    let (secret, public) = key_pair().await?;
    if STANDARD.encode(&public) != claims.controller_key { bail!("本机身份与远控许可不一致"); }
    let secret = sign::SecretKey::from_slice(&secret).ok_or_else(|| anyhow!("设备私钥无效"))?;
    let input = format!("NestLink-login-v2:{permit}:{connection_id}");
    let proof = STANDARD.encode(sign::sign_detached(input.as_bytes(), &secret).to_bytes());
    let envelope = serde_json::to_vec(&Envelope { permit: permit.to_owned(), proof })?;
    if auth.epoch != EPOCH.load(Ordering::SeqCst) || !ready() { bail!("账号授权已结束"); }
    Ok(PreparedPermit { envelope, guard: SessionGuard::start(claims.jti.clone(), auth.epoch), claims })
}
pub fn attach(request: &mut hbb_common::message_proto::LoginRequest, prepared: &[u8]) {
    request.special_fields.mut_unknown_fields().add_length_delimited(PERMIT_FIELD, prepared.to_vec());
}
pub async fn accept(login: &hbb_common::message_proto::LoginRequest) -> ResultType<Arc<SessionGuard>> {
    let auth = snapshot()?;
    let Some(UnknownValueRef::LengthDelimited(bytes)) = login.special_fields.unknown_fields().get(PERMIT_FIELD) else { bail!("连接缺少已登录账号的远控许可"); };
    if bytes.len() > 6144 { bail!("远控许可超出长度限制"); }
    let envelope: Envelope = serde_json::from_slice(bytes)?;
    let claims = verify_permit(&envelope.permit, &auth.presence.permit_trust)?;
    if claims.host_device != auth.request.device_id || claims.host_session != auth.presence.session_id ||
        claims.host_id != Config::get_id() || claims.controller_id != login.my_id || login.session_id == 0 ||
        STANDARD.encode(Config::get_key_pair().1) != claims.host_key { bail!("远控许可与连接设备不一致"); }
    let key = sign::PublicKey::from_slice(&STANDARD.decode(&claims.controller_key)?).ok_or_else(|| anyhow!("连接设备公钥无效"))?;
    let signature = sign::Signature::from_bytes(&STANDARD.decode(&envelope.proof)?).map_err(|_| anyhow!("连接设备签名无效"))?;
    if !sign::verify_detached(&signature, format!("NestLink-login-v2:{}:{}", envelope.permit, login.session_id).as_bytes(), &key) { bail!("连接设备身份证明无效"); }
    authorized_request(&auth, reqwest::Method::POST, &format!("/api/v2/remote/permits/{}/accept", claims.jti),
        Some(serde_json::json!({ "connection_id": login.session_id.to_string() }))).await?;
    if auth.epoch != EPOCH.load(Ordering::SeqCst) || !ready() { bail!("账号授权已结束"); }
    Ok(SessionGuard::start(claims.jti, auth.epoch))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> serde_json::Value {
        serde_json::from_str(include_str!("../../contracts/nestlink-auth.v2-vectors.json")).unwrap()
    }

    #[test]
    fn node_signature_fixture_binds_realm_lifetime_and_native_identity() {
        let value = fixture();
        let trust: Trust = serde_json::from_value(value["trust"].clone()).unwrap();
        let token = value["permit"].as_str().unwrap();
        let now = value["now"].as_u64().unwrap();
        let claims = verify_permit_at(token, &trust, now).unwrap();
        assert_eq!(claims.controller_id, "123456789");
        assert_eq!(claims.host_id, "987654321");
        assert!(verify_permit_at(token, &trust, now + 44).is_ok());
        assert!(verify_permit_at(token, &trust, now + 45).is_err());
        assert!(verify_permit_at(token, &trust, now - 6).is_err());
        let foreign = Trust { realm: "foreign-realm".into(), ..trust.clone() };
        assert!(verify_permit_at(token, &foreign, now).is_err());
        let mut altered = token.as_bytes().to_vec();
        altered[5] = if altered[5] == b'A' { b'B' } else { b'A' };
        assert!(verify_permit_at(std::str::from_utf8(&altered).unwrap(), &trust, now).is_err());
        assert!(verify_permit_at(&format!("{token}.extra"), &trust, now).is_err());
    }

    #[test]
    fn node_login_proof_uses_full_u64_connection_id_without_numeric_rounding() {
        let value = fixture();
        let key = sign::PublicKey::from_slice(&STANDARD.decode(value["trust"]["public_key"].as_str().unwrap()).unwrap()).unwrap();
        let signature = sign::Signature::from_bytes(&STANDARD.decode(value["login_proof"].as_str().unwrap()).unwrap()).unwrap();
        let id = value["connection_id"].as_str().unwrap().parse::<u64>().unwrap();
        let input = format!("NestLink-login-v2:{}:{id}", value["permit"].as_str().unwrap());
        assert_eq!(input, value["login_input"].as_str().unwrap());
        assert!(sign::verify_detached(&signature, input.as_bytes(), &key));
        assert!(!sign::verify_detached(&signature, format!("{input}0").as_bytes(), &key));
    }

    #[test]
    fn ipc_debug_output_never_discloses_account_token() {
        let auth = AuthRequest { origin: "https://test.example.com".into(), device_id: "example-device".into(), access_token: "secret-token-must-not-be-logged".into() };
        assert!(!format!("{auth:?}").contains(&auth.access_token));
    }
}
