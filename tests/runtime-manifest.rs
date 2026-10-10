// Run the production version/identity gate against an actual installed bundle.
#[path = "../client/src/homedesk_runtime_compatibility.rs"]
mod runtime_compatibility;

fn main() {
    let path = std::env::args().nth(1).expect("runtime.json path required");
    let manifest: serde_json::Value = serde_json::from_slice(
        &std::fs::read(path).expect("read installed runtime metadata")).expect("runtime metadata JSON");
    let parent = manifest["parent_executable"].as_str().expect("parent executable").to_owned();
    assert!(matches!(parent.as_str(), "homedesk.exe" | "homedesk"));
    assert_eq!(env!("CARGO_PKG_VERSION"), "14.0.0");
    assert_eq!(manifest["version"], "14.0.0");
    assert_eq!(runtime_compatibility::validate(&manifest, &parent), Ok(()));

    for version in ["13.0.0", "12.0.0", "", "14.0.0-fake"] {
        let mut changed = manifest.clone();
        changed["version"] = version.into();
        assert_eq!(runtime_compatibility::validate(&changed, &parent), Err("RUNTIME_INCOMPATIBLE"));
    }
    for version in [serde_json::Value::Null, serde_json::json!(13)] {
        let mut changed = manifest.clone();
        changed["version"] = version;
        assert_eq!(runtime_compatibility::validate(&changed, &parent), Err("RUNTIME_INCOMPATIBLE"));
    }
    for parent_value in ["other.exe", "../homedesk.exe", ""] {
        let mut changed = manifest.clone();
        changed["parent_executable"] = parent_value.into();
        assert_eq!(runtime_compatibility::validate(&changed, &parent), Err("INTEGRITY_FAILED"));
    }
    let mut missing = manifest.clone();
    missing.as_object_mut().unwrap().remove("parent_executable");
    assert_eq!(runtime_compatibility::validate(&missing, &parent), Err("INTEGRITY_FAILED"));
    println!("11 runtime compatibility/identity cases passed using the built 14.0.0 manifest.");
}
