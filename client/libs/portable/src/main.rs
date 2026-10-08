#![windows_subsystem = "windows"]

use std::{
    path::PathBuf, // HOMEDESK: 路径边界校验已移到独立缓存模块。
    process::{Command, Stdio},
};

use bin_reader::BinaryReader;

pub mod bin_reader;
mod homedesk_cache; // HOMEDESK: 缓存作用域、所有权和链接校验放在独立模块。
#[cfg(windows)]
mod ui;

#[cfg(windows)]
const APP_METADATA: &[u8] = include_bytes!("../app_metadata.toml");
#[cfg(not(windows))]
const APP_METADATA: &[u8] = &[];
const APP_PREFIX: &str = env!("HOMEDESK_PORTABLE_NAMESPACE"); // HOMEDESK: 只使用构建期已校验的品牌缓存命名空间。
const APPNAME_RUNTIME_ENV_KEY: &str = "RUSTDESK_APPNAME";
#[cfg(windows)]
const SET_FOREGROUND_WINDOW_ENV_KEY: &str = "SET_FOREGROUND_WINDOW";

fn setup(
    reader: BinaryReader,
    dir: Option<PathBuf>,
    clear: bool,
    _args: &Vec<String>,
    _ui: &mut bool,
) -> Option<PathBuf> {
    // HOMEDESK: 只准备本包版本目录；任何校验或删除失败都停止解包。
    let Some(base) = dir.or_else(dirs::data_local_dir) else {
        eprintln!("无法确定便携缓存目录，已停止启动");
        return None;
    };
    let mut manifest = reader.exe.clone();
    for file in &reader.files {
        manifest.push_str(&file.path);
        manifest.push_str(&String::from_utf8_lossy(file.md5_code));
    }
    let package_id = format!("{:x}", md5::compute(manifest));
    let cache = match homedesk_cache::CacheScope::new(&base, APP_PREFIX, APP_METADATA, &package_id)
        .and_then(|scope| scope.prepare(clear)) {
        Ok(cache) => cache,
        Err(error) => { eprintln!("便携缓存安全检查失败，已停止启动：{error}"); return None; }
    };
    if cache.changed() {
        #[cfg(windows)]
        if _args.is_empty() {
            *_ui = true;
            ui::setup();
        }
    }
    for file in reader.files.iter() {
        let target = match cache.target(&file.path) { // HOMEDESK: 解包前禁止路径越界及重解析点。
            Ok(target) => target,
            Err(error) => { eprintln!("便携包文件路径校验失败：{error}"); return None; }
        };
        file.write_to_file(cache.path());
        let verified = cache.target(&file.path).is_ok() && std::fs::read(&target)
            .map(|bytes| format!("{:x}", md5::compute(bytes)) == String::from_utf8_lossy(file.md5_code))
            .unwrap_or(false); // HOMEDESK: 上游写文件忽略错误，本处必须验证结果后才能启动。
        if !verified { eprintln!("便携包文件写入或完整性校验失败，已停止启动"); return None; }
    }
    #[cfg(windows)]
    { // HOMEDESK: 辅助程序目标也须校验链接边界，复制失败不接管其他进程。
        let target = match cache.target(win::WIN_TOPMOST_INJECTED_PROCESS_EXE) {
            Ok(target) => target,
            Err(error) => { eprintln!("辅助程序缓存路径无效：{error}"); return None; }
        };
        if let Err(error) = win::copy_runtime_broker(&target) {
            eprintln!("辅助程序复制失败，已停止启动且未终止其他进程：{error}");
            return None;
        }
    }
    #[cfg(linux)]
    reader.configure_permission(cache.path());
    if let Err(error) = cache.mark_ready() { // HOMEDESK: 全部文件验证完成才落盘就绪元数据。
        eprintln!("便携缓存就绪标记写入失败：{error}");
        return None;
    }
    match cache.target(&reader.exe) { // HOMEDESK: 最终启动文件也必须位于本包版本目录。
        Ok(exe) if exe.is_file() => Some(exe),
        _ => { eprintln!("便携包启动程序无效，已停止启动"); None }
    }
}

fn use_null_stdio() -> bool {
    #[cfg(windows)]
    {
        // When running in CMD on Windows 7, using Stdio::inherit() with spawn returns an "invalid handle" error.
        // Since using Stdio::null() didn’t cause any issues, and determining whether the program is launched from CMD or by double-clicking would require calling more APIs during startup, we also use Stdio::null() when launched by double-clicking on Windows 7.
        let is_windows_7 = is_windows_7();
        println!("is windows7: {}", is_windows_7);
        return is_windows_7;
    }
    #[cfg(not(windows))]
    false
}

#[cfg(windows)]
fn is_windows_7() -> bool {
    use windows::Wdk::System::SystemServices::RtlGetVersion;
    use windows::Win32::System::SystemInformation::OSVERSIONINFOW;

    unsafe {
        let mut version_info = OSVERSIONINFOW::default();
        version_info.dwOSVersionInfoSize = std::mem::size_of::<OSVERSIONINFOW>() as u32;

        if RtlGetVersion(&mut version_info).is_ok() {
            // Windows 7 is version 6.1
            println!(
                "Windows version: {}.{}",
                version_info.dwMajorVersion, version_info.dwMinorVersion
            );
            return version_info.dwMajorVersion == 6 && version_info.dwMinorVersion == 1;
        }
    }
    false
}

fn execute(path: PathBuf, args: Vec<String>, _ui: bool) {
    println!("executing {}", path.display());
    // setup env
    let exe = std::env::current_exe().unwrap_or_default();
    let exe_name = exe.file_name().unwrap_or_default();
    // run executable
    let mut cmd = Command::new(path);
    cmd.args(args);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(winapi::um::winbase::CREATE_NO_WINDOW);
        if _ui {
            cmd.env(SET_FOREGROUND_WINDOW_ENV_KEY, "1");
        }
    }

    cmd.env(APPNAME_RUNTIME_ENV_KEY, exe_name);
    if use_null_stdio() {
        cmd.stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
    } else {
        cmd.stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit());
    }
    let _child = cmd.spawn();

    #[cfg(windows)]
    if _ui {
        match _child {
            Ok(child) => unsafe {
                winapi::um::winuser::AllowSetForegroundWindow(child.id() as u32);
            },
            Err(e) => {
                eprintln!("{:?}", e);
            }
        }
    }
}

fn main() {
    let mut args = Vec::new();
    let mut arg_exe = Default::default();
    let mut i = 0;
    for arg in std::env::args() {
        if i == 0 {
            arg_exe = arg.clone();
        } else {
            args.push(arg);
        }
        i += 1;
    }
    let click_setup = args.is_empty() && arg_exe.to_lowercase().ends_with("install.exe");
    #[cfg(windows)]
    let quick_support = args.is_empty() && win::is_quick_support_exe(&arg_exe);
    #[cfg(not(windows))]
    let quick_support = false;

    let mut ui = false;
    let reader = BinaryReader::default();
    if let Some(exe) = setup(
        reader,
        None,
        click_setup || args.contains(&"--silent-install".to_owned()),
        &args,
        &mut ui,
    ) {
        if click_setup {
            args = vec!["--install".to_owned()];
        } else if quick_support {
            args = vec!["--quick_support".to_owned()];
        }
        execute(exe, args, ui);
    } else {
        std::process::exit(1); // HOMEDESK: 解包或所有权校验失败不能返回成功退出码。
    }
}

#[cfg(windows)]
mod win {
    use std::{fs, io, path::Path}; // HOMEDESK: 复制缓存不再启动全机 taskkill。

    // Used for privacy mode(magnifier impl).
    pub const RUNTIME_BROKER_EXE: &'static str = "C:\\Windows\\System32\\RuntimeBroker.exe";
    pub const WIN_TOPMOST_INJECTED_PROCESS_EXE: &'static str = env!("HOMEDESK_PORTABLE_BROKER_EXE"); // HOMEDESK: 与主客户端保持相同品牌辅助进程名。

    pub(super) fn copy_runtime_broker(target_file: &Path) -> io::Result<()> { // HOMEDESK: 只复制已校验的当前版本目标，错误向上传递。
        let src = RUNTIME_BROKER_EXE;
        if target_file.exists() {
            if let (Ok(src_file), Ok(tgt_file)) = (fs::read(src), fs::read(&target_file)) {
                let src_md5 = format!("{:x}", md5::compute(&src_file));
                let tgt_md5 = format!("{:x}", md5::compute(&tgt_file));
                if src_md5 == tgt_md5 {
                    return Ok(());
                }
            }
        }
        fs::copy(src, target_file).map(|_| ()) // HOMEDESK: 在用文件复制失败时拒绝继续，不接管其他实例。
    }

    /// Check if the executable is a Quick Support version.
    /// Note: This function must be kept in sync with `src/core_main.rs`.
    #[inline]
    pub(super) fn is_quick_support_exe(exe: &str) -> bool {
        let exe = exe.to_lowercase();
        exe.contains("-qs-") || exe.contains("-qs.exe") || exe.contains("_qs.exe")
    }
}
