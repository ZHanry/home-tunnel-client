// HOMEDESK: 受管隧道进程独立于远控；命令不落入普通配置，许可撤销同步终止 Job。
use serde::{Deserialize, Serialize};
use std::sync::Mutex;

#[derive(Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub action: String,
    pub owner: String,
    #[serde(default)] pub origin: String,
    #[serde(default)] pub user_id: String,
    #[serde(default)] pub permission: String,
    #[serde(default)] pub name: String,
    #[serde(default)] pub code: String,
    #[serde(skip)] serial: u64,
}

#[derive(Clone, Default, Serialize)]
struct View {
    owner: String,
    phase: String,
    code: String,
    device_id: String,
    agent_state: String,
}

struct Controller {
    view: View,
    serial: u64,
    stopped_owners: std::collections::HashSet<String>,
    #[cfg(windows)] job: Option<std::sync::Arc<platform::Job>>,
    #[cfg(windows)] state_path: Option<std::path::PathBuf>,
}
lazy_static::lazy_static! {
    static ref CONTROLLER: Mutex<Controller> = Mutex::new(Controller {
        view: View { phase: "stopped".into(), ..View::default() },
        serial: 0,
        stopped_owners: std::collections::HashSet::new(),
        #[cfg(windows)] job: None,
        #[cfg(windows)] state_path: None,
    });
}

pub fn stop_all() {
    let mut controller = CONTROLLER.lock().unwrap();
    let owner = controller.view.owner.clone();
    if !owner.is_empty() { controller.stopped_owners.insert(owner); }
    #[cfg(windows)] if let Some(job) = controller.job.take() { job.terminate(); }
    controller.view.phase = "stopped".into();
    controller.serial = controller.serial.wrapping_add(1);
    controller.view.owner.clear();
}

fn valid_owner(value: &str) -> bool {
    value.len() == 32 && value.bytes().all(|c| c.is_ascii_hexdigit())
}
fn valid_user(value: &str) -> bool {
    value.len() == 36 && value.bytes().enumerate().all(|(i,c)|
        if [8,13,18,23].contains(&i) { c == b'-' } else { c.is_ascii_hexdigit() })
}
fn allowed(request: &Request) -> bool {
    valid_owner(&request.owner) && valid_user(&request.user_id)
        && crate::homedesk_config::home_tunnel_allowed()
        && !request.permission.is_empty()
        && request.permission == crate::homedesk_config::home_tunnel_permission()
        && crate::homedesk_config::normalize_portal_origin(&request.origin).as_deref() == Some(request.origin.as_str())
        && hbb_common::config::LocalConfig::get_option("homedesk-home-tunnel-origin") == request.origin
}

pub fn command(value: &str) {
    if value.len() > 8192 { return; }
    let Ok(mut request) = serde_json::from_str::<Request>(value) else { return; };
    if !valid_owner(&request.owner) { return; }
    if request.action == "stop" {
        let mut controller = CONTROLLER.lock().unwrap();
        controller.stopped_owners.insert(request.owner.clone());
        if controller.view.owner == request.owner {
            #[cfg(windows)] if let Some(job) = controller.job.take() { job.terminate(); }
            controller.view.phase = "stopped".into();
            controller.serial = controller.serial.wrapping_add(1);
            controller.view.owner.clear();
        }
        return;
    }
    if !matches!(request.action.as_str(), "inspect" | "enroll" | "run") || !allowed(&request)
        || request.name.chars().count() > 120 || request.name.chars().any(char::is_control)
        || (request.action == "enroll" && (request.code.len() < 16 || request.code.len() > 256
            || request.code.chars().any(|c| c.is_control() || c.is_whitespace()))) { return; }
    {
        let mut controller = CONTROLLER.lock().unwrap();
        if controller.stopped_owners.contains(&request.owner) { return; }
        #[cfg(windows)] if let Some(job) = controller.job.take() { job.terminate(); }
        controller.view = View { owner: request.owner.clone(), phase: "working".into(), ..View::default() };
        controller.serial = controller.serial.wrapping_add(1);
        request.serial = controller.serial;
    }
    #[cfg(windows)] std::thread::spawn(move || {
        if let Err(code) = platform::execute(&request) {
            {
                let mut controller = CONTROLLER.lock().unwrap();
                if controller.view.owner == request.owner && controller.serial == request.serial {
                    if let Some(job) = controller.job.take() { job.terminate(); }
                }
            }
            update(&request, "error", code, "", "");
        }
    });
    #[cfg(not(windows))] update(&request, "error", "PLATFORM_UNSUPPORTED", "", "");
}

fn update(request: &Request, phase: &str, code: &str, device: &str, state: &str) {
    if !allowed(request) { return; }
    let mut controller = CONTROLLER.lock().unwrap();
    if controller.view.owner != request.owner || controller.serial != request.serial { return; }
    controller.view.phase = phase.to_owned();
    controller.view.code = code.to_owned();
    if valid_user(device) { controller.view.device_id = device.to_owned(); }
    controller.view.agent_state = state.to_owned();
}

pub fn status() -> String {
    let controller = CONTROLLER.lock().unwrap();
    let mut view = controller.view.clone();
    #[cfg(windows)] if view.phase == "running" {
        if let Some(path) = &controller.state_path {
            if platform::regular(path).is_ok() {
                if let Ok(bytes) = std::fs::read(path) {
                    if bytes.len() <= 2 * 1024 * 1024 {
                        if let Ok(state) = serde_json::from_slice::<serde_json::Value>(&bytes) {
                            if let Some(agent) = state.get("agent_state").and_then(|v| v.as_str()) {
                                if matches!(agent, "Online" | "Offline" | "Starting" | "Applying" | "Degraded" | "Error" | "Revoked" | "ExpiredStop" | "RepairRequired") {
                                    view.agent_state = agent.to_owned();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    serde_json::to_string(&view).unwrap_or_else(|_| "{}".into())
}

// HOMEDESK: 页面仅比较已确认的远控配置指纹，不接收或保存服务器公钥。
pub fn network_identity() -> String {
    use sha2::{Digest, Sha256};
    let profile = crate::homedesk_config::active_profile();
    if profile.server.is_empty() || profile.key.is_empty() { return "{}".into(); }
    let mut server = profile.server.trim().to_ascii_lowercase();
    if !server.contains(':') { server.push_str(":21116"); }
    serde_json::json!({"server": server,
        "key_sha256": format!("{:x}", Sha256::digest(profile.key.trim().as_bytes()))}).to_string()
}

#[cfg(windows)]
mod platform {
    use super::*;
    use sha2::{Digest, Sha256};
    use std::{fs, io::{BufRead, BufReader, Write}, path::{Path, PathBuf}, process::{Command, Stdio}, sync::Arc};
    use std::os::windows::{fs::MetadataExt, io::AsRawHandle, process::CommandExt};
    use winapi::um::{jobapi2::{AssignProcessToJobObject, CreateJobObjectW, SetInformationJobObject, TerminateJobObject},
        handleapi::CloseHandle, winnt::{JobObjectExtendedLimitInformation, JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE}};

    pub struct Job(usize);
    impl Job {
        fn new(child: &std::process::Child) -> Result<Arc<Self>, &'static str> {
            unsafe {
                let handle = CreateJobObjectW(std::ptr::null_mut(), std::ptr::null());
                if handle.is_null() { return Err("JOB_FAILED"); }
                let job = Arc::new(Job(handle as usize));
                let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
                limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                if SetInformationJobObject(handle, JobObjectExtendedLimitInformation, &mut limits as *mut _ as _, std::mem::size_of_val(&limits) as _) == 0
                    || AssignProcessToJobObject(handle, child.as_raw_handle() as _) == 0 { return Err("JOB_FAILED"); }
                Ok(job)
            }
        }
        pub fn terminate(&self) { unsafe { TerminateJobObject(self.0 as _, 1); } }
    }
    impl Drop for Job { fn drop(&mut self) { unsafe { CloseHandle(self.0 as _); } } }

    pub fn regular(path: &Path) -> Result<(), &'static str> {
        let metadata = fs::symlink_metadata(path).map_err(|_| "RUNTIME_MISSING")?;
        if !metadata.is_file() || metadata.file_type().is_symlink() || metadata.file_attributes() & 0x400 != 0 { return Err("UNSAFE_PATH"); }
        Ok(())
    }
    fn verify(path: &Path, expected: &str) -> Result<(), &'static str> {
        regular(path)?;
        if expected.len() != 64 || !expected.bytes().all(|c| c.is_ascii_hexdigit()) { return Err("INTEGRITY_FAILED"); }
        let bytes = fs::read(path).map_err(|_| "INTEGRITY_FAILED")?;
        let actual = format!("{:x}", Sha256::digest(bytes));
        if actual != expected.to_ascii_lowercase() { return Err("INTEGRITY_FAILED"); }
        Ok(())
    }
    fn paths(request: &Request) -> Result<(PathBuf, PathBuf), &'static str> {
        let executable = std::env::current_exe().map_err(|_| "RUNTIME_MISSING")?.canonicalize().map_err(|_| "RUNTIME_MISSING")?;
        let app = executable.parent().ok_or("UNSAFE_PATH")?;
        let runtime = app.join("tunnel-runtime");
        let metadata = fs::symlink_metadata(&runtime).map_err(|_| "RUNTIME_MISSING")?;
        if !metadata.is_dir() || metadata.file_attributes() & 0x400 != 0 { return Err("UNSAFE_PATH"); }
        let manifest_path = runtime.join("runtime.json");
        regular(&manifest_path)?;
        let manifest: serde_json::Value = serde_json::from_slice(&fs::read(manifest_path).map_err(|_| "INTEGRITY_FAILED")?).map_err(|_| "INTEGRITY_FAILED")?;
        if manifest["version"] != "10.1.0" || manifest["parent_executable"].as_str() != executable.file_name().and_then(|v| v.to_str()) { return Err("INTEGRITY_FAILED"); }
        let helper = runtime.join("homedesk-tunnel-helper.exe");
        verify(&helper, manifest["helper_sha256"].as_str().ok_or("INTEGRITY_FAILED")?)?;
        verify(&runtime.join("home-tunnel-agent.exe"), "0be9d77918aad26539692fa80b0c2b0a8e7ab0bb8ed85de63f5e0456a2fcaef0")?;
        let config = hbb_common::config::Config::file();
        let root = config.parent().ok_or("UNSAFE_PATH")?.join("tunnel-local");
        let scope = format!("{:x}", Sha256::digest(format!("{}\0{}", request.origin, request.user_id).as_bytes()));
        let directory = root.join(scope);
        fs::create_dir_all(&directory).map_err(|_| "STATE_PROTECTION_FAILED")?;
        for parent in [&root, &directory] {
            let meta = fs::symlink_metadata(parent).map_err(|_| "UNSAFE_PATH")?;
            if !meta.is_dir() || meta.file_attributes() & 0x400 != 0 { return Err("UNSAFE_PATH"); }
        }
        Ok((helper, directory.join("state.json")))
    }
    pub fn execute(request: &Request) -> Result<(), &'static str> {
        let (helper, state_path) = paths(request)?;
        if !allowed(request) { return Err("PERMISSION_CHANGED"); }
        let mut command = Command::new(helper);
        command.args([request.action.as_str(), "--state"]).arg(&state_path)
            .args(["--origin", request.origin.as_str(), "--parent", &std::process::id().to_string(), "--name", request.name.as_str()])
            .creation_flags(0x08000000).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).env_clear();
        // HOMEDESK: 目录地址来自本机已确认配置，远控 ID 来自现有后台；不接受界面自报身份。
        if request.action == "run" {
            let profile = crate::homedesk_config::active_profile();
            let key_hash = format!("{:x}", Sha256::digest(profile.key.trim().as_bytes()));
            command.args(["--remote-id", crate::ipc::get_id().trim(),
                "--remote-server", profile.server.as_str(), "--remote-key-sha256", key_hash.as_str()]);
        }
        for key in ["SystemRoot", "WINDIR", "TEMP", "TMP", "APPDATA", "LOCALAPPDATA", "USERPROFILE", "USERNAME", "USERDOMAIN"] {
            if let Some(value) = std::env::var_os(key) { command.env(key, value); }
        }
        let mut child = command.spawn().map_err(|_| "START_FAILED")?;
        let job = match Job::new(&child) { Ok(job) => job, Err(code) => { let _ = child.kill(); return Err(code); } };
        if !allowed(request) { job.terminate(); return Ok(()); }
        {
            let mut controller = CONTROLLER.lock().unwrap();
            if controller.view.owner != request.owner || controller.serial != request.serial { job.terminate(); return Ok(()); }
            controller.job = Some(job.clone());
            controller.state_path = Some(state_path);
        }
        // 同步撤销先终止 Job；未收到门闩的助手不会发出任何网络请求。
        if !allowed(request) { job.terminate(); return Ok(()); }
        if let Some(mut input) = child.stdin.take() {
            input.write_all(b"HOMEDESK_AGENT_ALLOWED\n").map_err(|_| "START_FAILED")?;
            if request.action == "enroll" {
                input.write_all(request.code.as_bytes()).map_err(|_| "START_FAILED")?;
                input.write_all(b"\n").map_err(|_| "START_FAILED")?;
            }
        }
        if let Some(output) = child.stdout.take() {
            for line in BufReader::new(output).lines() {
                let line = line.map_err(|_| "RUNTIME_FAILED")?;
                if line.len() > 8192 { job.terminate(); return Err("RUNTIME_FAILED"); }
                let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) else { continue; };
                let phase = value["phase"].as_str().unwrap_or("error");
                if !matches!(phase, "registered" | "needs_enrollment" | "running" | "error") { continue; }
                update(request, phase, value["code"].as_str().unwrap_or("RUNTIME_FAILED"),
                    value["device_id"].as_str().unwrap_or(""), value["agent_state"].as_str().unwrap_or(""));
            }
        }
        let result = child.wait().map_err(|_| "RUNTIME_FAILED")?;
        if !allowed(request) { return Ok(()); }
        let mut controller = CONTROLLER.lock().unwrap();
        if controller.view.owner == request.owner && controller.serial == request.serial {
            controller.job = None;
            if request.action == "run" && controller.view.phase == "running" {
                controller.view.phase = "error".into(); controller.view.code = "AGENT_STOPPED".into();
            } else if !result.success() && controller.view.phase == "working" {
                controller.view.phase = "error".into(); controller.view.code = "RUNTIME_FAILED".into();
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn identity_validation_rejects_path_and_command_inputs() {
        assert!(valid_owner("0123456789abcdef0123456789abcdef"));
        assert!(!valid_owner("../another-user"));
        assert!(valid_user("12345678-1234-1234-1234-123456789abc"));
        assert!(!valid_user("12345678/1234/1234/1234/123456789abc"));
        assert!(serde_json::from_str::<Request>(r#"{"action":"run","owner":"0123456789abcdef0123456789abcdef","command":"anything"}"#).is_err());
    }
}
