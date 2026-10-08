// HOMEDESK: Windows 辅助进程只按本应用目录的真实映像路径认领，不按全机文件名终止。
use std::{io, path::{Path, PathBuf}};

pub fn broker_target(current_exe: &Path, basename: &str) -> io::Result<PathBuf> {
    let namespace = basename.strip_prefix("RuntimeBroker_")
        .and_then(|value| value.strip_suffix(".exe"))
        .filter(|value| !value.is_empty() && value.len() <= 64
            && value.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-'))
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "辅助进程名称无效"))?;
    let _ = namespace;
    let exe = current_exe.canonicalize()?;
    let directory = exe.parent().ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "程序目录无效"))?;
    let target = directory.join(basename);
    let metadata = std::fs::symlink_metadata(&target)?;
    if !metadata.is_file() || metadata.file_type().is_symlink() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "辅助进程必须是本程序目录中的普通文件"));
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        if metadata.file_attributes() & 0x400 != 0 {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "辅助进程不能使用重解析点"));
        }
    }
    let target = target.canonicalize()?;
    if target.parent() != Some(directory) {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "辅助进程不能越过本程序目录"));
    }
    Ok(target)
}

pub fn is_owned_broker(target: &Path, process_image: &Path) -> bool {
    let Ok(image) = process_image.canonicalize() else { return false; };
    #[cfg(windows)]
    { target.as_os_str().to_string_lossy().eq_ignore_ascii_case(&image.as_os_str().to_string_lossy()) }
    #[cfg(not(windows))]
    { target == image }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs, time::{SystemTime, UNIX_EPOCH}};

    #[test]
    fn broker_ownership_requires_this_executable_directory() {
        let root = std::env::temp_dir().join(format!("homedesk-process-fixture-{}-{}", std::process::id(), SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()));
        let app = root.join("app");
        let other = root.join("other");
        fs::create_dir_all(&app).unwrap();
        fs::create_dir_all(&other).unwrap();
        let exe = app.join("client.exe");
        let broker = app.join("RuntimeBroker_fixture.exe");
        let unrelated = other.join("RuntimeBroker_fixture.exe");
        for path in [&exe, &broker, &unrelated] { fs::write(path, b"fixture").unwrap(); }
        let target = broker_target(&exe, "RuntimeBroker_fixture.exe").unwrap();
        assert!(is_owned_broker(&target, &broker));
        assert!(!is_owned_broker(&target, &unrelated));
        assert!(!is_owned_broker(&target, &other.join("missing.exe")));
        for invalid in ["RuntimeBroker_rustdesk.exe/../other", "../RuntimeBroker_fixture.exe", "RuntimeBroker.exe", "RuntimeBroker_.exe"] {
            assert!(broker_target(&exe, invalid).is_err());
        }
        let resolved = root.canonicalize().unwrap();
        let parent = std::env::temp_dir().canonicalize().unwrap();
        assert!(resolved.starts_with(&parent));
        assert!(root.file_name().unwrap().to_string_lossy().starts_with("homedesk-process-fixture-"));
        fs::remove_dir_all(&resolved).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn linked_broker_cannot_claim_an_external_executable() {
        use std::os::unix::fs::symlink;
        let root = std::env::temp_dir().join(format!("homedesk-process-link-fixture-{}-{}", std::process::id(), SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()));
        let app = root.join("app");
        fs::create_dir_all(&app).unwrap();
        let exe = app.join("client.exe");
        let external = root.join("external.exe");
        fs::write(&exe, b"fixture").unwrap();
        fs::write(&external, b"fixture").unwrap();
        symlink(&external, app.join("RuntimeBroker_fixture.exe")).unwrap();
        assert!(broker_target(&exe, "RuntimeBroker_fixture.exe").is_err());
        let resolved = root.canonicalize().unwrap();
        assert!(resolved.starts_with(std::env::temp_dir().canonicalize().unwrap()));
        assert!(root.file_name().unwrap().to_string_lossy().starts_with("homedesk-process-link-fixture-"));
        fs::remove_dir_all(&resolved).unwrap();
    }
}
