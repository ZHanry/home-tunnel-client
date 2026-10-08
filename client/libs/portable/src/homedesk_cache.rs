// HOMEDESK: 便携缓存只操作本品牌、本版本、带本包标记的无链接目录。
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::{Component, Path, PathBuf},
};

const OWNER_FILE: &str = ".homedesk-portable-owner";
const META_FILE: &str = "meta.toml";
const MAX_MARKER: u64 = 512;

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}

pub fn namespace_valid(value: &str) -> bool {
    if value.is_empty() || value.len() > 64 ||
        !value.bytes().all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-')) {
        return false;
    }
    let upper = value.to_ascii_uppercase();
    !matches!(upper.as_str(), "CON" | "PRN" | "AUX" | "NUL") &&
        !["COM", "LPT"].iter().any(|prefix| upper.strip_prefix(prefix)
            .is_some_and(|number| number.len() == 1 && matches!(number.as_bytes()[0], b'1'..=b'9')))
}

pub fn metadata_timestamp(bytes: &[u8]) -> io::Result<u64> {
    let text = std::str::from_utf8(bytes).map_err(|_| invalid("便携包元数据不是有效 UTF-8"))?;
    let mut found = None;
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') { continue; }
        let Some((name, value)) = line.split_once('=') else {
            return Err(invalid("便携包元数据格式无效"));
        };
        if name.trim() != "timestamp" { continue; }
        if found.is_some() { return Err(invalid("便携包版本时间戳重复")); }
        let value = value.trim();
        if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
            return Err(invalid("便携包版本时间戳无效"));
        }
        let timestamp: u64 = value.parse().map_err(|_| invalid("便携包版本时间戳越界"))?;
        if timestamp == 0 { return Err(invalid("便携包版本时间戳不能为零")); }
        found = Some(timestamp);
    }
    found.ok_or_else(|| invalid("便携包缺少版本时间戳"))
}

fn has_reparse(metadata: &fs::Metadata) -> bool {
    if metadata.file_type().is_symlink() { return true; }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        if metadata.file_attributes() & 0x400 != 0 { return true; }
    }
    false
}

fn no_links(path: &Path) -> io::Result<()> {
    if !path.is_absolute() { return Err(invalid("便携缓存必须使用绝对路径")); }
    let mut prefix = PathBuf::new();
    for component in path.components() {
        if matches!(component, Component::ParentDir | Component::CurDir) {
            return Err(invalid("便携缓存路径不能包含相对跳转"));
        }
        prefix.push(component.as_os_str());
        // Windows 盘符前缀不是可独立查询的目录，等待 RootDir 再检查。
        if matches!(component, Component::Prefix(_)) { continue; }
        match fs::symlink_metadata(&prefix) {
            Ok(metadata) if has_reparse(&metadata) => return Err(invalid("便携缓存路径包含链接或重解析点")),
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

fn plain_directory(path: &Path) -> io::Result<()> {
    no_links(path)?;
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_dir() || has_reparse(&metadata) {
        return Err(invalid("便携缓存目录无效"));
    }
    Ok(())
}

fn make_directory(path: &Path) -> io::Result<()> {
    no_links(path)?;
    match fs::create_dir(path) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
        Err(error) => return Err(error),
    }
    plain_directory(path)
}

fn read_small(path: &Path) -> io::Result<Vec<u8>> {
    no_links(path)?;
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_file() || metadata.len() > MAX_MARKER || has_reparse(&metadata) {
        return Err(invalid("便携缓存标记无效"));
    }
    let mut bytes = Vec::new();
    File::open(path)?.take(MAX_MARKER + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_MARKER { return Err(invalid("便携缓存标记过大")); }
    Ok(bytes)
}

fn relative_path(value: &str) -> io::Result<PathBuf> {
    if value.is_empty() || value.bytes().any(|byte| byte < 32 || byte == 127 || byte == b':') {
        return Err(invalid("便携包文件路径无效"));
    }
    let normalized = value.replace('\\', "/");
    // 上游 generate.py 从 os.walk('.') 生成恰好一个 ./ 前缀，先去掉这一合法形式。
    let normalized = normalized.strip_prefix("./").unwrap_or(&normalized);
    if normalized.is_empty() || normalized.split('/').any(|part| part.is_empty() || part == "." || part == "..") {
        return Err(invalid("便携包文件不能包含多余前缀或相对跳转"));
    }
    let path = Path::new(normalized);
    if path.components().any(|part| !matches!(part, Component::Normal(_))) ||
        normalized.ends_with('/') {
        return Err(invalid("便携包文件不能越过版本目录"));
    }
    // Windows 会规范化末尾空格和点，必须在所有平台拒绝这类伪装跳转。
    for part in path.components() {
        let name = part.as_os_str().to_str().ok_or_else(|| invalid("便携包文件名无效"))?;
        let stem = name.split('.').next().unwrap_or("");
        if name.ends_with('.') || name.ends_with(' ') ||
            name.chars().any(|character| "<>|?*".contains(character)) ||
            !namespace_valid(stem) && matches!(stem.to_ascii_uppercase().as_str(), "CON" | "PRN" | "AUX" | "NUL") ||
            ["COM", "LPT"].iter().any(|prefix| stem.to_ascii_uppercase().strip_prefix(prefix)
                .is_some_and(|number| number.len() == 1 && matches!(number.as_bytes()[0], b'1'..=b'9'))) {
            return Err(invalid("便携包文件名包含 Windows 保留形式"));
        }
    }
    Ok(path.to_path_buf())
}

fn scan_tree(path: &Path) -> io::Result<()> {
    for entry in fs::read_dir(path)? {
        let path = entry?.path();
        no_links(&path)?;
        let metadata = fs::symlink_metadata(&path)?;
        if has_reparse(&metadata) { return Err(invalid("便携缓存内部存在链接或重解析点")); }
        if metadata.is_dir() { scan_tree(&path)?; }
        else if !metadata.is_file() { return Err(invalid("便携缓存内部存在不支持的文件类型")); }
    }
    Ok(())
}

#[derive(Clone, Debug)]
pub struct CacheScope {
    base: PathBuf,
    namespace: String,
    timestamp: u64,
    package_id: String,
    version: PathBuf,
}

pub struct PreparedCache {
    scope: CacheScope,
    #[cfg(not(windows))]
    lock_path: PathBuf,
    lock: Option<File>,
    changed: bool,
}

impl Drop for PreparedCache {
    fn drop(&mut self) {
        // Windows 由排他句柄表示活跃锁，退出即释放；保留锁文件避免崩溃遗留和交换竞态。
        self.lock.take();
        // 非 Windows 仅供保守 std 探针，便携发布目前只支持 Windows。
        #[cfg(not(windows))]
        if no_links(&self.lock_path).is_ok() { let _ = fs::remove_file(&self.lock_path); }
    }
}

impl CacheScope {
    pub fn new(base: &Path, namespace: &str, metadata: &[u8], package_id: &str) -> io::Result<Self> {
        if !namespace_valid(namespace) { return Err(invalid("便携缓存品牌命名空间无效")); }
        if package_id.len() != 32 || !package_id.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return Err(invalid("便携包缓存身份无效"));
        }
        plain_directory(base)?;
        let base = fs::canonicalize(base)?;
        let timestamp = metadata_timestamp(metadata)?;
        let version = base.join(namespace).join("portable").join(timestamp.to_string());
        no_links(&version)?;
        Ok(Self { base, namespace: namespace.to_owned(), timestamp,
            package_id: package_id.to_ascii_lowercase(), version })
    }

    pub fn path(&self) -> &Path { &self.version }

    fn owner(&self) -> String {
        format!("HOMEDESK_PORTABLE_OWNER_V1\nnamespace={}\ntimestamp={}\npackage={}\n",
            self.namespace, self.timestamp, self.package_id)
    }

    fn validate_target(&self, target: &Path) -> io::Result<()> {
        if target != self.version { return Err(invalid("拒绝清理预期版本目录之外的目标")); }
        plain_directory(&self.base)?;
        no_links(target)?;
        let expected = self.base.join(&self.namespace).join("portable").join(self.timestamp.to_string());
        if target.exists() && fs::canonicalize(target)? != expected {
            return Err(invalid("便携缓存解析后的路径不是预期版本目录"));
        }
        Ok(())
    }

    fn verify_owner(&self) -> io::Result<()> {
        self.validate_target(&self.version)?;
        plain_directory(&self.version)?;
        if read_small(&self.version.join(OWNER_FILE))? != self.owner().as_bytes() {
            return Err(invalid("便携缓存没有本包的所有权标记，拒绝覆盖或删除"));
        }
        Ok(())
    }

    pub fn clear_version(&self, target: &Path) -> io::Result<()> {
        self.clear_version_using(target, |path| fs::remove_dir_all(path))
    }

    fn clear_version_using(&self, target: &Path, remove: impl FnOnce(&Path) -> io::Result<()>) -> io::Result<()> {
        self.validate_target(target)?;
        self.verify_owner()?;
        scan_tree(target)?;
        // 删除失败立即返回，调用方不得继续向半删除目录解包。
        remove(target)
    }

    pub fn prepare(&self, clear: bool) -> io::Result<PreparedCache> {
        self.validate_target(&self.version)?;
        let brand = self.base.join(&self.namespace);
        make_directory(&brand)?;
        let portable = brand.join("portable");
        make_directory(&portable)?;
        let lock_path = portable.join(format!(".{}.lock", self.timestamp));
        no_links(&lock_path)?;
        let mut options = OpenOptions::new();
        options.read(true).write(true);
        #[cfg(windows)]
        {
            use std::os::windows::fs::OpenOptionsExt;
            options.create(true).share_mode(0);
        }
        #[cfg(not(windows))]
        options.create_new(true);
        let lock = options.open(&lock_path)?;
        let mut prepared = PreparedCache { scope: self.clone(),
            #[cfg(not(windows))] lock_path,
            lock: Some(lock), changed: !self.version.exists() };
        if self.version.exists() {
            self.verify_owner()?;
            let matches = read_small(&self.version.join(META_FILE))
                .and_then(|bytes| metadata_timestamp(&bytes)).is_ok_and(|value| value == self.timestamp);
            if clear || !matches {
                self.clear_version(&self.version)?;
                prepared.changed = true;
            }
        }
        if !self.version.exists() {
            make_directory(&self.version)?;
            let mut marker = OpenOptions::new().write(true).create_new(true).open(self.version.join(OWNER_FILE))?;
            marker.write_all(self.owner().as_bytes())?;
            marker.sync_all()?;
        }
        self.verify_owner()?;
        Ok(prepared)
    }
}

impl PreparedCache {
    pub fn path(&self) -> &Path { self.scope.path() }
    pub fn changed(&self) -> bool { self.changed }

    pub fn target(&self, relative: &str) -> io::Result<PathBuf> {
        self.scope.verify_owner()?;
        let path = self.path().join(relative_path(relative)?);
        no_links(&path)?;
        Ok(path)
    }

    pub fn mark_ready(&self) -> io::Result<()> {
        self.scope.verify_owner()?;
        scan_tree(self.path())?;
        let path = self.target(META_FILE)?;
        let mut file = File::create(path)?;
        file.write_all(format!("timestamp = {}\n", self.scope.timestamp).as_bytes())?;
        file.sync_all()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};
    use std::sync::atomic::{AtomicU64, Ordering};

    const PACKAGE: &str = "11111111111111111111111111111111";
    static SEQUENCE: AtomicU64 = AtomicU64::new(0);
    struct Temporary { root: PathBuf, base: PathBuf }
    impl Temporary {
        fn new() -> Self {
            let stamp = SystemTime::now().duration_since(UNIX_EPOCH).expect("测试时钟").as_nanos();
            let parent = fs::canonicalize(std::env::temp_dir()).expect("测试临时根");
            let root = parent.join(format!("homedesk-cache-fixture-{}-{stamp}-{}", std::process::id(), SEQUENCE.fetch_add(1, Ordering::SeqCst)));
            fs::create_dir(&root).expect("创建合成目录");
            let base = root.join("base");
            fs::create_dir(&base).expect("创建合成数据根");
            Self { root, base }
        }
        fn scope(&self, name: &str, timestamp: u64) -> CacheScope {
            CacheScope::new(&self.base, name, format!("timestamp = {timestamp}\n").as_bytes(), PACKAGE)
                .expect("合成缓存作用域")
        }
    }
    impl Drop for Temporary {
        fn drop(&mut self) {
            let parent = fs::canonicalize(std::env::temp_dir()).expect("测试临时根");
            assert_eq!(self.root.parent(), Some(parent.as_path()));
            assert!(self.root.file_name().expect("测试目录名称").to_string_lossy().starts_with("homedesk-cache-fixture-"));
            if no_links(&self.root).is_ok() { fs::remove_dir_all(&self.root).expect("清理本次合成目录"); }
        }
    }

    #[test]
    fn metadata_fails_closed_and_namespace_is_checked() {
        for bytes in [b"".as_slice(), b"timestamp = 0", b"timestamp = nope", b"timestamp = 1\ntimestamp = 2", b"timestamp = 18446744073709551616", b"\xff"] {
            assert!(metadata_timestamp(bytes).is_err());
        }
        assert_eq!(metadata_timestamp(b"# fixture\ntimestamp = 123\n").expect("合法元数据"), 123);
        for name in ["", "../escape", "C:", "a/b", "a\\b", "CON", "com1"] { assert!(!namespace_valid(name)); }
        assert!(namespace_valid("homedesk_acceptance"));
    }

    #[test]
    fn brands_and_versions_keep_separate_directories() {
        let temp = Temporary::new();
        let old = temp.scope("alpha", 100).prepare(false).expect("旧版本缓存");
        assert!(old.changed());
        fs::write(old.target("keep.txt").expect("合成文件"), b"old").expect("写入合成文件");
        old.mark_ready().expect("版本就绪");
        let another = temp.scope("beta", 100).prepare(false).expect("另一品牌缓存");
        another.mark_ready().expect("版本就绪");
        let next = temp.scope("alpha", 200).prepare(false).expect("新版本缓存");
        assert_ne!(old.path(), another.path());
        assert_ne!(old.path(), next.path());
        assert_eq!(fs::read(old.path().join("keep.txt")).expect("旧文件保留"), b"old");
    }

    #[test]
    fn unknown_owner_and_outside_target_are_not_deleted() {
        let temp = Temporary::new();
        let scope = temp.scope("alpha", 100);
        fs::create_dir_all(scope.path()).expect("未知目录");
        fs::write(scope.path().join("user.txt"), b"user").expect("未知文件");
        assert!(scope.prepare(true).is_err());
        assert!(scope.clear_version(scope.path()).is_err());
        let outside = temp.root.join("outside");
        fs::create_dir(&outside).expect("测试范围外的合成目录");
        assert!(scope.clear_version(&outside).is_err());
        assert!(scope.path().join("user.txt").exists());
        assert!(outside.exists());
    }

    #[test]
    fn current_owner_can_reset_only_its_version_and_blocks_duplicate_unpack() {
        let temp = Temporary::new();
        let scope = temp.scope("alpha", 100);
        let cache = scope.prepare(false).expect("新缓存");
        assert!(scope.prepare(true).is_err());
        fs::write(cache.target("test.txt").expect("合成文件路径"), b"fixture").expect("合成文件");
        cache.mark_ready().expect("就绪标记");
        drop(cache);
        let cache = scope.prepare(true).expect("受控重置");
        assert!(!cache.path().join("test.txt").exists());
        assert!(cache.target("../outside").is_err());
        assert!(cache.target("data\\..\\outside").is_err());
        assert!(cache.target("C:\\outside").is_err());
        assert!(cache.target(".. \\outside").is_err());
        assert!(cache.target("CON.txt").is_err());
        cache.mark_ready().expect("就绪标记");
    }

    #[test]
    fn upstream_generate_paths_allow_only_one_initial_current_directory() {
        let temp = Temporary::new();
        let cache = temp.scope("alpha", 100).prepare(false).expect("合成缓存");
        assert_eq!(cache.target(".\\desktop_drop_plugin.dll").expect("真实打包文件形式"), cache.path().join("desktop_drop_plugin.dll"));
        assert_eq!(cache.target(".\\homedesk.exe").expect("真实启动文件形式"), cache.path().join("homedesk.exe"));
        assert_eq!(cache.target("./data/flutter_assets/AssetManifest.json").expect("真实资源文件形式"), cache.path().join("data").join("flutter_assets").join("AssetManifest.json"));
        for relative in ["././file", ".\\.\\file", "a/./file", "a/../file", "/absolute", "C:relative", "./", "", "file.", "file "] {
            assert!(cache.target(relative).is_err(), "应拒绝异常路径形式");
        }
    }

    #[test]
    fn delete_failure_returns_before_recreating_or_overwriting_cache() {
        let temp = Temporary::new();
        let scope = temp.scope("alpha", 100);
        let cache = scope.prepare(false).expect("新缓存");
        fs::write(cache.target("test.txt").expect("合成文件"), b"original").expect("写合成文件");
        cache.mark_ready().expect("就绪标记");
        drop(cache);
        let result = scope.clear_version_using(scope.path(), |_| Err(io::Error::new(io::ErrorKind::PermissionDenied, "合成删除失败")));
        assert!(result.is_err());
        assert_eq!(fs::read(scope.path().join("test.txt")).expect("原文件"), b"original");
    }

    #[cfg(windows)]
    #[test]
    fn windows_junction_cannot_redirect_a_cache_scope() {
        let temp = Temporary::new();
        fs::create_dir(temp.root.join("outside")).expect("合成链接目标");
        fs::write(temp.root.join("outside").join("keep.txt"), b"safe").expect("范围外合成文件");
        let output = std::process::Command::new("cmd")
            .current_dir(&temp.base).args(["/d", "/c", "mklink", "/J", "alpha", "..\\outside"]).output().expect("运行临时 Junction 创建命令");
        if !output.status.success() {
            eprintln!("未执行：当前环境不能创建合成 Junction");
            return;
        }
        assert!(CacheScope::new(&temp.base, "alpha", b"timestamp = 100", PACKAGE).is_err());
        assert_eq!(fs::read(temp.root.join("outside").join("keep.txt")).expect("范围外文件"), b"safe");
        fs::remove_dir(temp.base.join("alpha")).expect("只移除本次 Junction");
    }

    #[cfg(windows)]
    #[test]
    fn windows_in_use_file_failure_does_not_continue_extracting() {
        use std::os::windows::fs::OpenOptionsExt;
        let temp = Temporary::new();
        let scope = temp.scope("alpha", 100);
        let cache = scope.prepare(false).expect("合成缓存");
        let payload = cache.target("locked.txt").expect("合成文件路径");
        fs::write(&payload, b"original").expect("写合成文件");
        cache.mark_ready().expect("缓存就绪");
        drop(cache);
        let mut held = OpenOptions::new().read(true).share_mode(0).open(&payload).expect("本次合成文件锁");
        assert!(scope.prepare(true).is_err());
        let mut content = String::new();
        held.read_to_string(&mut content).expect("从本次合成句柄读取");
        assert_eq!(content, "original");
        drop(held);
    }

    #[cfg(windows)]
    #[test]
    fn windows_old_lock_file_is_recoverable_but_an_active_handle_is_exclusive() {
        let temp = Temporary::new();
        let scope = temp.scope("alpha", 100);
        let portable = temp.base.join("alpha").join("portable");
        fs::create_dir_all(&portable).expect("合成缓存父目录");
        let lock = portable.join(".100.lock");
        fs::write(&lock, b"old-lock-fixture").expect("合成崩溃遗留锁文件");
        let cache = scope.prepare(false).expect("无活跃句柄的遗留锁可以恢复");
        assert!(scope.prepare(false).is_err());
        cache.mark_ready().expect("缓存就绪");
        drop(cache);
        assert_eq!(fs::read(&lock).expect("锁文件保持原内容"), b"old-lock-fixture");
        let cache = scope.prepare(false).expect("关闭句柄后可以再次获取锁");
        assert!(!cache.changed());
    }
}
