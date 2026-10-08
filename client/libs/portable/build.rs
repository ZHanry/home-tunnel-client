#[path = "../../homedesk_build.rs"] // HOMEDESK: 安装包外壳复用同一品牌配置。
mod homedesk_build;

fn main() {
    let (app_name, executable_name) = match homedesk_build::resource_brand() { // HOMEDESK: 外壳缓存与资源复用同一份已校验品牌。
        Ok(brand) => brand,
        Err(error) => { eprintln!("{error}"); std::process::exit(1); }
    };
    println!("cargo:rustc-env=HOMEDESK_PORTABLE_NAMESPACE={executable_name}"); // HOMEDESK: 不再写入上游共享 rustdesk 缓存根。
    println!("cargo:rustc-env=HOMEDESK_PORTABLE_BROKER_EXE=RuntimeBroker_{executable_name}.exe"); // HOMEDESK: 与主客户端的辅助进程名保持一致。
    #[cfg(windows)]
    {
        use std::io::Write;
        let mut res = winres::WindowsResource::new();
        res.set("ProductName", &app_name) // HOMEDESK: 保留上游版权声明，只替换品牌相关字段。
            .set("FileDescription", &format!("{app_name} 家庭远控"))
            .set("InternalName", &executable_name)
            .set("OriginalFilename", &format!("{executable_name}.exe"));
        res.set_icon("../../res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("../../res/manifest.xml");
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}
